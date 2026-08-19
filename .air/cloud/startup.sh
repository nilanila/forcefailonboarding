#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if [ "${AIR_STARTUP_MODE:-}" = warmup ]; then
  WARMUP=1
else
  WARMUP=
fi

echo "==> Installing dependencies (npm ci)"
npm ci

echo "==> Starting Vite dev server in background"
nohup npm run dev -- --host 0.0.0.0 --port 3000 > /tmp/vite-dev.log 2>&1 &

healthcheck() {
  echo "==> Waiting for dev server on :3000 to respond"
  local last_log_len=0
  while true; do
    if curl -fsS -o /dev/null "http://localhost:3000/"; then
      echo "==> Dev server is responding on :3000"
      return 0
    fi
    local len
    len=$(wc -l < /tmp/vite-dev.log 2>/dev/null || echo 0)
    if [ "$len" != "$last_log_len" ]; then
      echo "---- vite log (last lines) ----"
      tail -n 5 /tmp/vite-dev.log 2>/dev/null || true
      last_log_len="$len"
    fi
    sleep 2
  done
}

if [ -n "${WARMUP}" ]; then
  healthcheck
fi

echo "==> startup.sh complete"
