#!/usr/bin/env bash
# probe_health.sh — API Logic Server liveness + auth + authorized-read probe.
#
# Usage (defaults shown):
#   HOST=localhost PORT=5656 ALS_USER=admin ALS_PASS=p RESOURCE=Customer scripts/probe_health.sh
#
# Steps:
#   1. server up        GET  http://HOST:PORT/api            expect HTTP 200
#   2. login            POST /api/auth/login {user,pass}     expect access_token
#      (if login fails but an unauthenticated GET succeeds, security is OFF -> SKIP, not FAIL)
#   3. authorized GET   GET  /api/RESOURCE/?page[limit]=1    expect HTTP 200 with "data"
#
# Prints PASS/FAIL per step. Exit 0 = healthy; exit N = step N failed.
# Requires: bash, curl, python3 (stdlib only).

set -u

HOST="${HOST:-localhost}"
PORT="${PORT:-5656}"
ALS_USER="${ALS_USER:-admin}"
ALS_PASS="${ALS_PASS:-p}"
RESOURCE="${RESOURCE:-Customer}"
BASE="http://${HOST}:${PORT}"

# Array (not string) so --noproxy '*' survives without glob expansion.
CURL=(curl -s --noproxy '*' --max-time 10)

# ---------- step 1: server up ----------
code=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "${BASE}/api" 2>/dev/null)
if [ "${code}" = "200" ]; then
    echo "PASS  1. server up: GET ${BASE}/api -> HTTP 200"
else
    echo "FAIL  1. server up: GET ${BASE}/api -> HTTP '${code:-000}' (000 = no connection)"
    echo "      Is the server running? From project root: python api_logic_server_run.py"
    echo "      Port busy instead? Look for: 'Port ${PORT} is in use by another program.'"
    exit 1
fi

# ---------- step 2: login ----------
login_body=$("${CURL[@]}" -X POST "${BASE}/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${ALS_USER}\",\"password\":\"${ALS_PASS}\"}" 2>/dev/null)
TOKEN=$(printf '%s' "${login_body}" | python3 -c '
import sys, json
try:
    print(json.load(sys.stdin).get("access_token", ""), end="")
except Exception:
    print("", end="")
')
if [ -n "${TOKEN}" ]; then
    echo "PASS  2. login: POST /api/auth/login as '${ALS_USER}' -> access_token (${#TOKEN} chars)"
else
    # Distinguish "security off" from "login broken".
    unauth=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "${BASE}/api/${RESOURCE}/?page%5Blimit%5D=1" 2>/dev/null)
    if [ "${unauth}" = "200" ]; then
        echo "SKIP  2. login: no token, but unauthenticated GET works -> security is OFF"
    else
        echo "FAIL  2. login: POST /api/auth/login as '${ALS_USER}' -> no access_token"
        echo "      Response was: $(printf '%s' "${login_body}" | head -c 200)"
        echo "      'Wrong username or password' -> check ALS_USER/ALS_PASS (sample DB: admin/p)"
        exit 2
    fi
fi

# ---------- step 3: authorized GET ----------
auth_header=()
[ -n "${TOKEN}" ] && auth_header=(-H "Authorization: Bearer ${TOKEN}")
body_file=$(mktemp)
code=$("${CURL[@]}" "${auth_header[@]}" -o "${body_file}" -w '%{http_code}' \
    "${BASE}/api/${RESOURCE}/?page%5Blimit%5D=1" 2>/dev/null)
if [ "${code}" = "200" ] && grep -q '"data"' "${body_file}"; then
    count=$(python3 -c '
import sys, json
try:
    print(json.load(open(sys.argv[1])).get("meta", {}).get("total", "?"), end="")
except Exception:
    print("?", end="")
' "${body_file}")
    echo "PASS  3. authorized GET /api/${RESOURCE}/ -> HTTP 200, meta.total=${count}"
    rm -f "${body_file}"
else
    echo "FAIL  3. authorized GET /api/${RESOURCE}/ -> HTTP ${code}"
    echo "      Response was: $(head -c 200 "${body_file}")"
    echo "      401 Missing Authorization Header -> token not sent; 404 -> wrong RESOURCE name (case-sensitive)"
    rm -f "${body_file}"
    exit 3
fi

echo "OK    all probes passed against ${BASE}"
exit 0
