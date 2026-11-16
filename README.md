# tailscale-exporter

> [!NOTE]
> This project — code, configuration and this README — was generated with AI assistance
> (Claude Code). Review it and check it fits your environment before relying on it.

A small Prometheus exporter for [headscale](https://github.com/juanfont/headscale). A shell
script polls the headscale API for nodes, renders them as Prometheus metrics with `jq`, and
an unprivileged nginx serves the result on port `8081` at `/metrics`.

## Metrics

Every series carries `hostname`, `id`, `ipv4` and `ipv6` labels.

| Metric | Type | Description |
|---|---|---|
| `tailscale_online` | gauge | `1` if the node is online, else `0` |
| `tailscale_last_seen_timestamp` | gauge | Last seen time as a unix timestamp |
| `tailscale_routes` | gauge | One series per subnet route, with `subnet` and `type` (`approved` / `available` / `primary`) labels |
| `tailscale_subnet_routes` | gauge | Number of subnet routes the node serves as primary |
| `tailscale_node_tag` | gauge | One series per tag, with a `tag` label |

## Running the container

```sh
docker run -d -p 8081:8081 \
  -e HEADSCALE_URL=https://headscale.example.com \
  -e HEADSCALE_API_KEY=... \
  ghcr.io/cc1-playground/tailscale-exporter:master

curl localhost:8081/metrics
```

Create an API key with `headscale apikeys create`.

| Variable | Default | Description |
|---|---|---|
| `HEADSCALE_URL` | — (required) | Base URL of the headscale server |
| `HEADSCALE_API_KEY` | — | API key. If unset, it is read from `APIKEY_FILE` |
| `APIKEY_FILE` | `/etc/headscale/apikey` | File holding the API key (e.g. a mounted secret) |
| `INTERVAL` | `60` | Seconds between refreshes |
| `MAX_FAILURES` | `3` | Consecutive failed refreshes before the metrics file is removed |
| `OUTPUT` | `/tmp/metrics.prom` | File the refresh loop writes and nginx serves |

### Behaviour

- The first refresh runs before nginx starts; if it fails (bad URL or key) the container exits.
- After that, a background loop refreshes every `INTERVAL` seconds and logs each result to stderr.
  Each request to headscale times out after 5 seconds.
- After `MAX_FAILURES` consecutive failures the metrics file is deleted, so `/metrics` returns
  `404` and Prometheus marks the target down instead of scraping stale data. The next successful
  refresh brings it back.
- Only `/metrics` is served; every other path returns `404`.
- [tini](https://github.com/krallin/tini) runs as PID 1: it reaps processes, forwards stop
  signals to nginx, and if nginx dies the container exits and takes the refresh loop with it.

## Running the script without Docker

`scripts/fetch.sh` works on its own; it needs `curl` and `jq`.

```sh
# Print to stdout
HEADSCALE_URL=https://headscale.example.com HEADSCALE_API_KEY=... scripts/fetch.sh
scripts/fetch.sh https://headscale.example.com "$KEY"   # positional args override env

# Write atomically for node_exporter's textfile collector, e.g. from cron
* * * * * OUTPUT=/var/lib/node_exporter/headscale.prom /usr/local/bin/headscale-exporter.sh
```

Passing the key as an argument exposes it in `ps`; prefer the environment or `APIKEY_FILE`.

## Image

Built from `Dockerfile` for `linux/amd64`, with pinned dependencies:

- base: `quay.io/nginx/nginx-unprivileged:1.31.8-alpine3.24-perl`, pinned by digest
- curl: binary and libcurl copied from `alpine/curl:8.23.0`, pinned by digest. Its other shared
  libraries come from the base image, so both must stay on the same Alpine release.
- tini: `v0.19.0` static musl build, verified against its sha256
- jq: installed with `apk`

```sh
docker build -t tailscale-exporter .
```

## CI

`.github/workflows/docker.yml` builds and pushes the image to
`ghcr.io/<owner>/<repo>` on pushes to `master` that touch the image sources, and can be run
manually. Actions are pinned by commit SHA.

## Repository layout

| Path | Purpose |
|---|---|
| `scripts/fetch.sh` | Fetches nodes from headscale and renders metrics |
| `scripts/90-headscale-exporter.sh` | Entrypoint hook: initial refresh and the background refresh loop |
| `nginx/default.conf` | Serves `/metrics` on port 8081 |
| `Dockerfile` | Image build |

`.gitignore` is an allowlist: new files must be added to it explicitly (or use `git add -f`).

## License

Public domain, under the [Unlicense](LICENSE).
