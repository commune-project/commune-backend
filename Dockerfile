# BuildKit is required for named build contexts and cache mounts.
# The MyGO checkout is supplied as the named context "mygo" by compose.yaml.

ARG GO_VERSION=1.27.1

FROM golang:${GO_VERSION}-bookworm AS build

ARG MYGO_GENERATE=false
ARG GOPROXY=https://proxy.golang.org,direct

ENV GOCACHE=/root/.cache/go-build
ENV GOMODCACHE=/go/pkg/mod
ENV GOPROXY=${GOPROXY}
ENV GOFLAGS=-buildvcs=false

WORKDIR /src/commune-backend

# MyGO comes from a local BuildKit context, never from a network clone.
# prelude and lib are needed by the checked-in generated Go sources.
# cmd, internal and ebnf.txt are only needed when MYGO_GENERATE=true.
COPY --from=mygo go.mod go.sum /src/mygo/
COPY --from=mygo prelude /src/mygo/prelude
COPY --from=mygo lib /src/mygo/lib
COPY --from=mygo cmd /src/mygo/cmd
COPY --from=mygo internal /src/mygo/internal
COPY --from=mygo ebnf.txt /src/mygo/ebnf.txt

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

COPY . .

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    set -eu; \
    if [ "${MYGO_GENERATE}" = "true" ]; then \
      make generate MYGO_ROOT=/src/mygo BUILD_DIR=/tmp/mygo-build; \
    fi; \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/commune ./cmd/commune

FROM alpine:3.22 AS runtime

RUN apk add --no-cache ca-certificates curl jq \
    && addgroup -S -g 10001 commune \
    && adduser -S -D -H -u 10001 -G commune commune \
    && mkdir -p /var/lib/commune/media /run/commune /etc/commune \
    && chown -R commune:commune /var/lib/commune /run/commune \
    && chmod 0700 /run/commune

COPY --from=build /out/commune /usr/local/bin/commune
COPY deploy/entrypoint.sh /usr/local/bin/commune-entrypoint
COPY deploy/healthcheck.sh /usr/local/bin/healthcheck
RUN chmod 0755 /usr/local/bin/commune /usr/local/bin/commune-entrypoint /usr/local/bin/healthcheck

USER 10001:10001
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/commune-entrypoint"]
CMD ["serve"]
