#!/bin/sh
# Runs from /docker-entrypoint.d before nginx starts; refreshes /tmp/metrics.prom in the background.
set -eu

INTERVAL="${INTERVAL:-60}"
MAX_FAILURES="${MAX_FAILURES:-3}"
export OUTPUT="${OUTPUT:-/tmp/metrics.prom}"

log() { echo "headscale-exporter: $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >&2; }

# First run in the foreground so a bad URL/key fails container startup.
/usr/local/bin/headscale-exporter.sh
log "initial refresh ok"

(
  failures=0
  while sleep "${INTERVAL}"; do
    if /usr/local/bin/headscale-exporter.sh; then
      [ "${failures}" -gt 0 ] && log "refresh recovered after ${failures} failure(s)"
      failures=0
      log "refresh ok"
    else
      failures=$((failures + 1))
      log "refresh failed (${failures}/${MAX_FAILURES})"
      if [ "${failures}" -ge "${MAX_FAILURES}" ] && [ -e "${OUTPUT}" ]; then
        rm -f "${OUTPUT}"
        log "removed ${OUTPUT} after ${failures} consecutive failures; /metrics now returns 404"
      fi
    fi
  done
) &
