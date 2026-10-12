#!/usr/bin/env bash
# Usage: ./scripts/smoke-test.sh http://YOUR_PUBLIC_URL
set -euo pipefail
URL="${1:?public url required}"; URL="${URL%/}"
echo "== /health";  curl -fsS --retry 10 --retry-delay 5 --retry-connrefused "$URL/health"; echo
echo "== /";        curl -fsS "$URL/"; echo
echo "== grafana";  curl -fsS -o /dev/null -w 'HTTP %{http_code}\n' "$URL/grafana/login"
echo "OK"
