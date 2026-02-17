import argparse
import subprocess
import sys
import os

# Check for Python 3.11+ for tomllib
if sys.version_info < (3, 11):
    print("Error: Python 3.11 or newer is required to run this script.")
    sys.exit(1)

import tomllib

def run_command(command, check=True):
    print(f"Running: {' '.join(command)}")
    try:
        subprocess.run(command, check=check)
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {e}")
        if check:
            sys.exit(1)

def get_gleam_deps():
    try:
        with open("gleam.toml", "rb") as f:
            data = tomllib.load(f)
            deps = list(data.get("dependencies", {}).keys())
            dev_deps = list(data.get("dev-dependencies", {}).keys())
            return deps, dev_deps
    except FileNotFoundError:
        print("gleam.toml not found.")
        return [], []

def get_cargo_deps():
    cargo_path = "native/waffle/Cargo.toml"
    try:
        with open(cargo_path, "rb") as f:
            data = tomllib.load(f)
            deps = list(data.get("dependencies", {}).keys())
            dev_deps = list(data.get("dev-dependencies", {}).keys())
            return deps, dev_deps, cargo_path
    except FileNotFoundError:
        print(f"{cargo_path} not found.")
        return [], [], cargo_path

def update_gleam(deps, dev_deps):
    print("Updating Gleam dependencies...")
    if deps:
        run_command(["gleam", "add"] + deps)
    if dev_deps:
        # Note: gleam add supports multiple packages with --dev flag applied to all?
        # Actually `gleam add --dev pkg1 pkg2` adds both as dev deps.
        run_command(["gleam", "add", "--dev"] + dev_deps)

def update_cargo(deps, dev_deps, manifest_path):
    print("Updating Cargo dependencies...")
    if deps:
        run_command(["cargo", "add"] + deps + ["--manifest-path", manifest_path])
    if dev_deps:
        run_command(["cargo", "add", "--dev"] + dev_deps + ["--manifest-path", manifest_path])

def update_mise():
    print("Updating Mise pinned versions (installed tools)...")
    # user said "Update all pinned versions in mise". Since they are 'latest',
    # 'mise upgrade' updates the installed tools to the latest version.
    run_command(["mise", "upgrade"])

def update_locked():
    print("Updating lockfiles only...")
    if os.path.exists("gleam.toml"):
        run_command(["gleam", "update"])

    cargo_path = "native/waffle/Cargo.toml"
    if os.path.exists(cargo_path):
        run_command(["cargo", "update", "--manifest-path", cargo_path])

    print("Mise does not use a lockfile in the same way (uses mise.toml). Skipping.")

def main():
    parser = argparse.ArgumentParser(description="Update project dependencies.")
    parser.add_argument("mode", choices=["update", "update-locked"], help="Mode to run: 'update' (updates config files) or 'update-locked' (updates lockfiles only)")
    args = parser.parse_args()

    if args.mode == "update":
        # Gleam
        deps, dev_deps = get_gleam_deps()
        if deps or dev_deps:
            update_gleam(deps, dev_deps)

        # Cargo
        c_deps, c_dev_deps, c_path = get_cargo_deps()
        if c_deps or c_dev_deps:
            update_cargo(c_deps, c_dev_deps, c_path)

        # Mise
        if os.path.exists("mise.toml"):
            update_mise()

    elif args.mode == "update-locked":
        update_locked()

if __name__ == "__main__":
    main()
