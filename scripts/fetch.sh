#!/bin/sh
# /usr/local/bin/headscale-exporter.sh
# Alpine deps: apk add --no-cache curl jq
#
# Usage:
#   headscale-exporter.sh [URL] [API_KEY]                   # print to stdout
#   HEADSCALE_URL=https://hs.example.com HEADSCALE_API_KEY=... headscale-exporter.sh
#   OUTPUT=/var/lib/node_exporter/headscale.prom headscale-exporter.sh
#
# Config (positional args override env):
#   HEADSCALE_URL      base URL of headscale (required)
#   HEADSCALE_API_KEY  API key; if unset, read from APIKEY_FILE
#   APIKEY_FILE        default /etc/headscale/apikey
#   OUTPUT             write atomically to this file instead of stdout
#
# Cron (every minute):
#   * * * * * OUTPUT=/var/lib/node_exporter/headscale.prom /usr/local/bin/headscale-exporter.sh

set -eu

HEADSCALE_URL="${1:-${HEADSCALE_URL:-}}"
HEADSCALE_API_KEY="${2:-${HEADSCALE_API_KEY:-}}"
APIKEY_FILE="${APIKEY_FILE:-/etc/headscale/apikey}"
OUTPUT="${OUTPUT:-}"

[ -n "${HEADSCALE_URL}" ] || { echo "HEADSCALE_URL is not set" >&2; exit 1; }
HEADSCALE_URL="${HEADSCALE_URL%/}"

if [ -z "${HEADSCALE_API_KEY}" ]; then
  [ -r "${APIKEY_FILE}" ] || { echo "HEADSCALE_API_KEY is not set and cannot read ${APIKEY_FILE}" >&2; exit 1; }
  HEADSCALE_API_KEY="$(tr -d '[:space:]' < "${APIKEY_FILE}")"
fi
[ -n "${HEADSCALE_API_KEY}" ] || { echo "empty api key" >&2; exit 1; }

JQ_PROGRAM='
def labels:
  "hostname=\"\(.name)\"," +
  "id=\"\(.id)\"," +
  "ipv4=\"\(first(.ipAddresses[]? | select(contains("."))) // "")\"," +
  "ipv6=\"\(first(.ipAddresses[]? | select(contains(":"))) // "")\"";

def routes($type; f):
  .nodes[] | . as $n | ($n | labels) as $l
  | ($n | f // [])[]
  | "tailscale_routes{\($l),subnet=\"\(.)\",type=\"\($type)\"} 1";

"# HELP tailscale_online Whether the node is online (1) or not (0)",
"# TYPE tailscale_online gauge",
(.nodes[] | "tailscale_online{\(labels)} \(if .online then 1 else 0 end)"),

"# HELP tailscale_last_seen_timestamp Last seen time as unix timestamp",
"# TYPE tailscale_last_seen_timestamp gauge",
(.nodes[] | select(.lastSeen != null)
  | "tailscale_last_seen_timestamp{\(labels)} \(.lastSeen | sub("\\.[0-9]+Z$"; "Z") | fromdate)"),

"# HELP tailscale_routes Subnet routes per node by type (approved/available/primary)",
"# TYPE tailscale_routes gauge",
routes("approved";  .approvedRoutes),
routes("available"; .availableRoutes),
routes("primary";   .subnetRoutes),

"# HELP tailscale_subnet_routes Number of subnet routes the node is serving as primary",
"# TYPE tailscale_subnet_routes gauge",
(.nodes[] | "tailscale_subnet_routes{\(labels)} \((.subnetRoutes // []) | length)"),

"# HELP tailscale_node_tag Tags assigned to the node",
"# TYPE tailscale_node_tag gauge",
(.nodes[] | . as $n | ($n | labels) as $l
  | ($n.tags // [])[]
  | "tailscale_node_tag{\($l),tag=\"\(.)\"} 1")
'

collect() {
  # Not piped directly: in a pipeline a curl failure would be masked by jq's exit status.
  # The header is fed on stdin (-H @-) so the API key never appears in curl's argv / ps.
  nodes="$(printf 'Authorization: Bearer %s\n' "${HEADSCALE_API_KEY}" |
    curl -fsS --max-time 5 -H @- "${HEADSCALE_URL}/api/v1/node")"
  printf '%s' "${nodes}" | jq -er "${JQ_PROGRAM}"
}

if [ -n "${OUTPUT}" ]; then
  tmp="$(mktemp "${OUTPUT}.XXXXXX")"
  trap 'rm -f "${tmp}"' EXIT
  collect > "${tmp}"
  chmod 644 "${tmp}"
  mv "${tmp}" "${OUTPUT}"
else
  collect
fi
