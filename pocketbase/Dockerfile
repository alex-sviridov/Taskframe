# pocketbase/Dockerfile
FROM alpine:3.20
ARG PB_VERSION=0.28.4
RUN apk add --no-cache ca-certificates unzip curl \
    && curl -Lo /tmp/pb.zip https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip \
    && unzip /tmp/pb.zip -d /pb \
    && rm /tmp/pb.zip
WORKDIR /pb
EXPOSE 8090
ENTRYPOINT ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090"]
