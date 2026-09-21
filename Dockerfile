# syntax=docker/dockerfile:1

FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION=3.47.2
RUN apt-get update && apt-get install -y --no-install-recommends git curl ca-certificates xz-utils unzip \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /flutter
ENV PATH="/flutter/bin:${PATH}"
RUN flutter config --no-analytics && flutter precache --web

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release --pwa-strategy=offline-first

FROM nginx:1.27-alpine
RUN rm -rf /usr/share/nginx/html/* /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/build/web /usr/share/nginx/html
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN mkdir -p /tmp/client_temp /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp \
    && chmod +x /docker-entrypoint.sh \
    && chown -R nginx:nginx /usr/share/nginx/html /etc/nginx /var/cache/nginx /tmp/client_temp /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp

USER nginx
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/ >/dev/null || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
