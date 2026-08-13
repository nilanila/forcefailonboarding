#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

export CI=true

# Detect WARMUP (snapshot-baking env-setup companion) vs TASK (real workspace boot).
_ps="$(ps -ax -o args= 2>/dev/null)"
if grep -q 'air-workspace-start\.sh' <<<"$_ps"; then
  WARMUP=
else
  WARMUP=1
fi
echo "[startup] mode: $([ -n "${WARMUP:-}" ] && echo WARMUP || echo TASK)"

# NOTE: this repo's package-lock.json intentionally pins lodash@3.10.1 while
# package.json/App.jsx require lodash 4.x (_.upperCase). `npm ci` refuses to
# install on that mismatch ("Invalid: lock file's lodash@3.10.1 does not
# satisfy lodash@4.17.21") — use `npm install` so it resolves and proceeds.
echo "[startup] installing npm dependencies..."
npm install

echo "[startup] starting Vite dev server in background on :3000"
nohup npm run dev -- --host 0.0.0.0 >/tmp/vite-dev.log 2>&1 &

healthcheck() {
  echo "[healthcheck] waiting for the dev server to answer on :3000..."
  while true; do
    code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/ || true)"
    if [ "$code" = "200" ]; then
      echo "[healthcheck] dev server responded 200 OK"
      return 0
    fi
    echo "[healthcheck] not ready yet (last status: ${code:-none}), retrying..."
    sleep 2
  done
}

if [ -n "${WARMUP:-}" ]; then
  healthcheck
fi

echo "[startup] done"
