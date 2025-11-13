#!/usr/bin/env python3
"""
File watcher that automatically reloads Frappe DocType JSON files when they change.
This runs alongside the asset watcher to provide hot-reloading for JSON configuration files.
"""
import os
import sys
import time
import json
import subprocess
from datetime import datetime
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# Configuration
SITE_NAME = os.environ.get("FRAPPE_SITE", "synthlane.localhost")
BENCH_PATH = "/workspace/frappe-bench"
APPS_TO_WATCH = ["frappe", "erpnext", "synthlane_ims"]


class DocTypeReloadHandler(FileSystemEventHandler):
    """Handler for DocType JSON file changes"""
    
    def __init__(self):
        self.last_reload = {}
        self.debounce_seconds = 1  # Wait 1 second before reloading
        
    def on_modified(self, event):
        if event.is_directory:
            return
            
        file_path = Path(event.src_path)
        
        # Only watch JSON files
        if file_path.suffix != ".json":
            return
        
        # Convert to absolute path and normalize
        try:
            file_path = file_path.resolve()
        except:
            return
            
        # Check if file is within bench path
        try:
            bench_path = Path(BENCH_PATH).resolve()
            if not str(file_path).startswith(str(bench_path)):
                return
        except:
            return
            
        # Get relative path from bench
        try:
            rel_path = file_path.relative_to(bench_path)
            parts = rel_path.parts
        except:
            return
        
        # Pattern: apps/{app}/{app}/{module}/{doctype}/{name}/{name}.json
        # Example: apps/erpnext/erpnext/accounts/onboarding_step/setup_taxes/setup_taxes.json
        if len(parts) < 6:
            return
            
        # Check if path starts with apps/
        if parts[0] != "apps":
            return
            
        # Get app name (second part)
        if len(parts) < 2:
            return
            
        app_name = parts[1]
        if app_name not in APPS_TO_WATCH:
            return
            
        # Check if this matches DocType structure: apps/{app}/{app}/{module}/{doctype}/{name}/{name}.json
        if len(parts) >= 6:
            # parts[0] = apps
            # parts[1] = app_name (e.g., erpnext)
            # parts[2] = app_name again (e.g., erpnext)
            # parts[3] = module (e.g., accounts)
            # parts[4] = doctype (e.g., onboarding_step)
            # parts[5] = docname (e.g., setup_taxes)
            # parts[6] = filename (e.g., setup_taxes.json)
            
            if parts[2] == app_name and len(parts) >= 7:
                module = parts[3]
                doctype = parts[4]
                docname = parts[5]
                filename = parts[6]
                
                # Verify filename matches docname
                if filename == f"{docname}.json":
                    # Debounce: don't reload if we just reloaded this file
                    file_key = f"{module}.{doctype}.{docname}"
                    current_time = time.time()
                    
                    if file_key in self.last_reload:
                        if current_time - self.last_reload[file_key] < self.debounce_seconds:
                            return
                    
                    self.last_reload[file_key] = current_time
                    
                    print(f"\n[Reload Watcher] Detected change in {file_path.name}")
                    print(f"[Reload Watcher] Reloading: module={module}, doctype={doctype}, docname={docname}")
                    
                    # Update the modified timestamp in JSON to ensure reload happens
                    self.update_json_timestamp(file_path)
                    
                    self.reload_doc(module, doctype, docname)
    
    def update_json_timestamp(self, file_path):
        """Update the modified timestamp in JSON file to current time"""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            # Update modified timestamp to current time
            current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")
            data['modified'] = current_time
            
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=1, ensure_ascii=False)
                # Add newline at end of file
                f.write('\n')
            
            print(f"[Reload Watcher] ✓ Updated modified timestamp in JSON to: {current_time}")
        except Exception as e:
            print(f"[Reload Watcher] ⚠ Could not update JSON timestamp: {e}")
    
    def reload_doc(self, module, doctype, docname):
        """Reload a document using bench reload-doc and clear cache"""
        try:
            os.chdir(BENCH_PATH)
            
            # First, reload the document
            cmd = [
                "bench",
                "--site", SITE_NAME,
                "reload-doc",
                module,
                doctype,
                docname,
                "--force"
            ]
            
            print(f"[Reload Watcher] Running: {' '.join(cmd)}")
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                print(f"[Reload Watcher] ✓ Successfully reloaded {doctype} > {docname}")
                if result.stdout:
                    print(f"[Reload Watcher] Output: {result.stdout}")
                
                # Clear cache for the doctype to ensure fresh data
                clear_cache_cmd = [
                    "bench",
                    "--site", SITE_NAME,
                    "clear-cache"
                ]
                
                print(f"[Reload Watcher] Clearing cache...")
                cache_result = subprocess.run(
                    clear_cache_cmd,
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                
                if cache_result.returncode == 0:
                    print(f"[Reload Watcher] ✓ Cache cleared successfully")
                else:
                    print(f"[Reload Watcher] ⚠ Cache clear had issues: {cache_result.stderr}")
                    
            else:
                print(f"[Reload Watcher] ✗ Error reloading {doctype} > {docname}")
                print(f"[Reload Watcher] Error: {result.stderr}")
                if result.stdout:
                    print(f"[Reload Watcher] Output: {result.stdout}")
                
        except subprocess.TimeoutExpired:
            print(f"[Reload Watcher] ✗ Timeout reloading {doctype} > {docname}")
        except Exception as e:
            print(f"[Reload Watcher] ✗ Exception: {e}")
            import traceback
            print(f"[Reload Watcher] Traceback: {traceback.format_exc()}")


def main():
    """Main function to start the file watcher"""
    print(f"[Reload Watcher] Starting DocType JSON file watcher...")
    print(f"[Reload Watcher] Site: {SITE_NAME}")
    print(f"[Reload Watcher] Watching apps: {', '.join(APPS_TO_WATCH)}")
    
    event_handler = DocTypeReloadHandler()
    observer = Observer()
    
    # Watch all app directories
    for app in APPS_TO_WATCH:
        app_path = Path(BENCH_PATH) / "apps" / app
        if app_path.exists():
            observer.schedule(event_handler, str(app_path), recursive=True)
            print(f"[Reload Watcher] Watching: {app_path}")
    
    observer.start()
    print(f"[Reload Watcher] Ready! Changes to JSON files will be automatically reloaded.\n")
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[Reload Watcher] Stopping...")
        observer.stop()
    
    observer.join()


if __name__ == "__main__":
    main()

