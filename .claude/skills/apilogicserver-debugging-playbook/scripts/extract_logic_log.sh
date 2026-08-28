#!/usr/bin/env bash
# extract_logic_log.sh — pull the LogicBank transaction blocks out of a noisy server log.
#
# Usage:
#   scripts/extract_logic_log.sh <logfile>          # e.g. logs/als.log, or a captured console log
#
# Output: each logic transaction as a numbered block —
#   from  "Logic Phase: ROW LOGIC (session=0x...)"
#   through COMMIT / AFTER_FLUSH phases and the "These Rules Fired" summary
#   to    "Logic Phase: COMPLETE(session=0x...)"
# ANSI color codes are stripped. A block that ends in "--- Logging error ---" instead of
# COMPLETE is flagged: that is the constraint-violation path (see the debugging-playbook
# skill: 17.03.19 short_format_exception bug) — the 400/rollback is still correct.
#
# Requires: bash, python3 (stdlib only).

set -u
if [ $# -ne 1 ] || [ ! -f "${1}" ]; then
    echo "usage: $0 <logfile>   (file not found: ${1:-<missing>})" >&2
    exit 1
fi

python3 - "$1" <<'PY'
import re, sys

ansi = re.compile(r'\x1b\[[0-9;]*[A-Za-z]|\x1b\][^\x07]*\x07')
path = sys.argv[1]

blocks, cur, in_block = [], [], False
with open(path, 'r', errors='replace') as f:
    for raw in f:
        line = ansi.sub('', raw.rstrip('\n'))
        starts_row = line.startswith('Logic Phase:') and 'ROW LOGIC' in line
        if starts_row:
            if in_block:
                blocks.append((cur, 'no COMPLETE (next transaction began)'))
            cur, in_block = [line], True
            continue
        if not in_block:
            continue
        if line.startswith('--- Logging error ---'):
            blocks.append((cur, 'ended by "--- Logging error ---" — constraint-violation '
                                'path; 400/rollback still correct (short_format_exception '
                                'bug, see debugging playbook)'))
            cur, in_block = [], False
            continue
        cur.append(line)
        if line.startswith('Logic Phase:') and 'COMPLETE' in line:
            blocks.append((cur, None))
            cur, in_block = [], False
if in_block and cur:
    blocks.append((cur, 'no COMPLETE (log truncated?)'))

if not blocks:
    print(f'No "Logic Phase: ROW LOGIC" blocks found in {path}.')
    print('Either no write transactions ran, or logic_logger is silenced '
          '(config/logging.yml -> loggers: logic_logger: level).')
    sys.exit(0)

for n, (lines, note) in enumerate(blocks, 1):
    m = re.search(r'session=(0x[0-9a-f]+)', lines[0])
    session = m.group(1) if m else '?'
    print('=' * 78)
    print(f'Transaction {n}  (session={session})' + (f'  [{note}]' if note else ''))
    print('=' * 78)
    # Drop trailing runs of blank lines inside the block for compactness.
    out, blank = [], 0
    for l in lines:
        blank = blank + 1 if l.strip() == '' else 0
        if blank <= 1:
            out.append(l)
    print('\n'.join(out))
    print()
print(f'{len(blocks)} logic transaction(s) extracted from {path}.')
PY
