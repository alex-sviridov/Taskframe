#!/bin/sh
# Rewrites <base href="..."> in the built index.html to $BASE_HREF (default
# "/") at container start, so the same image can be deployed at any HTTP
# subpath without a rebuild — see lib/features/account/account_providers.dart
# for how the app derives its API base URL from this at runtime.
#
# Also rewrites nginx.conf's PocketBase upstream to $PB_UPSTREAM (default
# "pocketbase:8090"), so the same image works against any PocketBase
# hostname (e.g. a k8s Service name that isn't "pocketbase") without a
# rebuild.
set -eu

BASE_HREF="${BASE_HREF:-/}"
PB_UPSTREAM="${PB_UPSTREAM:-pocketbase:8090}"

sed -i "s|<base href=\"[^\"]*\">|<base href=\"${BASE_HREF}\">|" \
  /usr/share/nginx/html/index.html

sed -i "s|__PB_UPSTREAM__|${PB_UPSTREAM}|" /etc/nginx/nginx.conf

exec "$@"
