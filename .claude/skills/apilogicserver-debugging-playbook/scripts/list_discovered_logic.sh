#!/usr/bin/env bash
# list_discovered_logic.sh — show what ALS auto-discovery WILL load, and flag files it will
# load but choke on (missing the required function).
#
# Usage (from project root):
#   scripts/list_discovered_logic.sh          # or: bash /path/to/list_discovered_logic.sh
#
# Mirrors the real discovery code in this project family (verified against 17.03.19):
#   logic/logic_discovery/auto_discovery.py  — os.walk (RECURSIVE), loads every *.py except
#       auto_discovery.py and __init__.py, then calls its module-level declare_logic().
#   api/api_discovery/auto_discovery.py      — walk, loads every *.py except auto_discovery.py,
#       then calls its add_service(app, api, project_dir, swagger_host, PORT, method_decorators).
# A file renamed away from .py (e.g. workflow_integration.pyZZ) is invisible to discovery —
# that is the supported way to disable one.
#
# Requires: bash, python3 (stdlib only). Read-only.

set -u
if [ ! -d "logic/logic_discovery" ] && [ ! -d "api/api_discovery" ]; then
    echo "Neither logic/logic_discovery/ nor api/api_discovery/ found." >&2
    echo "Run this from the project root (the directory containing api_logic_server_run.py)." >&2
    exit 1
fi

python3 - <<'PY'
import os, re, sys

def scan(base, required_fn, exclude_init):
    """Yield (relpath, has_required_fn, disabled_siblings) mirroring auto_discovery."""
    loaded, skipped, malformed = [], [], []
    if not os.path.isdir(base):
        return None
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d != '__pycache__']
        for f in sorted(files):
            rel = os.path.relpath(os.path.join(root, f))
            if f == 'auto_discovery.py' or (exclude_init and f == '__init__.py'):
                continue
            if not f.endswith('.py'):
                if re.search(r'\.py[A-Za-z_]+$', f):   # e.g. .pyZZ = deliberately disabled
                    skipped.append(rel)
                continue
            try:
                src = open(os.path.join(root, f), errors='replace').read()
            except OSError:
                src = ''
            ok = re.search(r'^\s*def\s+' + required_fn + r'\s*\(', src, re.M) is not None
            (loaded if ok else malformed).append(rel)
    return loaded, skipped, malformed

def report(title, base, required_fn, exclude_init):
    res = scan(base, required_fn, exclude_init)
    print(f'== {title} ({base}/) ==')
    if res is None:
        print('   directory not present\n')
        return 0
    loaded, skipped, malformed = res
    for p in loaded:
        print(f'   WILL LOAD   {p}')
    for p in skipped:
        print(f'   disabled    {p}   (not *.py — invisible to discovery)')
    for p in malformed:
        print(f'   !! BAD SHAPE {p}   (no top-level "def {required_fn}(" — '
              f'discovery will raise AttributeError at startup)')
    if not (loaded or skipped or malformed):
        print('   (no candidate files)')
    print(f'   -> {len(loaded)} file(s) will be discovered\n')
    return len(malformed)

bad  = report('Logic discovery — each file needs declare_logic()',
              'logic/logic_discovery', 'declare_logic', exclude_init=True)
bad += report('API discovery — each file needs add_service(app, api, project_dir, swagger_host, PORT, method_decorators)',
              'api/api_discovery', 'add_service', exclude_init=True)

print('Compare against the startup log lines "..discovered logic: [...]" and '
      '"..discovered services: [...]".')
sys.exit(1 if bad else 0)
PY
