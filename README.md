# taskframe

A smoke test of the Flutter + `flutter_riverpod` + `go_router` stack: no
domain logic yet, just wiring and infrastructure scaffolding (CI, lint,
formatting, tests) meant to be built on.

Run `make help` to see the available development commands (setup, format,
analyze, test, build, etc.) — see the `Makefile` for the full list.

## Deployment

`docker-compose.yml` builds and runs two services: `web` (Flutter web build
served by nginx, `Dockerfile`) and `pocketbase` (the backend). `make run`
builds and starts both.

`web`'s nginx proxies `/api/` to the PocketBase backend (see `nginx.conf`),
so the app talks to PocketBase same-origin and never needs its real
host/port configured separately. The upstream host:port is configurable at
container start (not baked into the image) via the `PB_UPSTREAM` environment
variable on the `web` container — default `pocketbase:8090`, the
docker-compose service name. Useful outside docker-compose (e.g. a k8s
Service with a different name), e.g.:

```sh
PB_UPSTREAM=my-pocketbase-service:8090 docker compose up -d web
```

An entrypoint script (`docker-entrypoint.sh`) rewrites `nginx.conf`'s
`proxy_pass` target to `$PB_UPSTREAM` at container start.

### Serving under an HTTP subpath

The `web` image can be served at any subpath (e.g.
`https://host/taskframe/`) without rebuilding: set the `BASE_HREF`
environment variable on the `web` container (default `/`), e.g.

```sh
BASE_HREF=/taskframe/ docker compose up -d web
```

An entrypoint script (`docker-entrypoint.sh`) rewrites `<base href>` in the
built `index.html` to `$BASE_HREF` at container start; the app then derives
its PocketBase base URL from that same `<base href>` at runtime, so API
calls stay under the same prefix. This assumes a reverse proxy/ingress that
strips the subpath prefix before forwarding to this container — nginx
itself is unaware of the prefix.

<!-- CI flow verification: 2026-09-12T06:17:39Z -->
