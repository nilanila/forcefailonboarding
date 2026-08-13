#!/usr/bin/env bash
# Startup script for the forcefailonboarding companion / task environment.
#
# NOTE: package.json declares "lodash": "^4.17.21" but package-lock.json's
# node_modules/lodash entry is pinned to 3.10.1 (an intentional mismatch —
# see FALSE_DEPENDENCIES_INFO.md). `npm ci` correctly refuses to install in
# that state, and the repo's own README instructions to "always use npm ci"
# would leave this environment permanently broken. We try npm ci first (in
# case the lockfile is ever fixed upstream) and fall back to npm install,
# mirroring the detection logic already in warmup-example.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

export CI=true
export npm_config_yes=true

# Detect WARMUP (env-setup companion) vs TASK (air-workspace-start.sh) mode.
_ps="$(ps -ax -o args= 2>/dev/null)"
if grep -q 'air-workspace-start\.sh' <<<"$_ps"; then
  WARMUP=
else
  WARMUP=1
fi

DEV_PORT=3000
DEV_LOG="/tmp/vite-dev.log"

log() { echo "[startup] $*"; }

install_deps() {
  log "installing npm dependencies..."
  if npm ci --no-audit --no-fund 2>&1; then
    log "npm ci succeeded"
    return
  fi
  log "npm ci failed (package-lock.json is intentionally out of sync with package.json in this repo) — falling back to npm install"
  npm install --no-audit --no-fund
  log "npm install completed"
}

verify_lodash() {
  # Guards against the known trap: a stale lodash 3.x would silently break
  # App.jsx's _.upperCase() call at runtime with no install-time signal.
  if ! node -e "const _=require('lodash'); if (typeof _.upperCase !== 'function') { console.error('lodash '+_.VERSION+' is missing upperCase()'); process.exit(1); }"; then
    log "ERROR: installed lodash does not provide upperCase() — dependency install did not fix the version mismatch"
    exit 1
  fi
}

build_smoke_test() {
  log "running production build as an install smoke test (also warms Vite/Rollup caches)..."
  npm run build
}

start_dev_server() {
  if curl -fsS "http://localhost:${DEV_PORT}/" >/dev/null 2>&1; then
    log "dev server already responding on port ${DEV_PORT}, not starting another instance"
    return
  fi
  log "starting Vite dev server on 0.0.0.0:${DEV_PORT}..."
  nohup npx vite --host 0.0.0.0 --port "${DEV_PORT}" >"${DEV_LOG}" 2>&1 &
  disown
}

# healthcheck: waits (no fixed timeout/retry cap) until the dev server is
# actually serving the app, then does one content-level sanity check.
healthcheck() {
  log "healthcheck: waiting for dev server on port ${DEV_PORT}..."
  local waited=0
  until body="$(curl -fsS "http://localhost:${DEV_PORT}/" 2>/dev/null)"; do
    waited=$((waited + 3))
    if [ $((waited % 15)) -eq 0 ]; then
      log "healthcheck: still waiting for http://localhost:${DEV_PORT}/ (${waited}s elapsed)"
    fi
    sleep 3
  done

  if ! grep -q '<div id="root">' <<<"$body"; then
    log "healthcheck: FAILED — root document did not contain the expected app mount point"
    log "healthcheck: last 40 lines of ${DEV_LOG}:"
    tail -n 40 "${DEV_LOG}" 2>/dev/null || true
    exit 1
  fi

  if ! curl -fsS "http://localhost:${DEV_PORT}/src/main.jsx" >/dev/null 2>&1; then
    log "healthcheck: FAILED — Vite could not transform /src/main.jsx"
    log "healthcheck: last 40 lines of ${DEV_LOG}:"
    tail -n 40 "${DEV_LOG}" 2>/dev/null || true
    exit 1
  fi

  log "healthcheck: OK — dev server is serving the app on port ${DEV_PORT}"
}

install_deps
verify_lodash
build_smoke_test
start_dev_server

if [ -n "${WARMUP:-}" ]; then
  healthcheck
else
  log "TASK mode: dev server starting in background, not blocking on readiness"
fi

log "startup complete"
