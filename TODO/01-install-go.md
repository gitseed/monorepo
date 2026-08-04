# Install Go 1.26 toolchain

## Why

Veronica's session driver (`app/driver/`) is a Go program. Building, testing,
and modifying it requires the Go toolchain.

- `go.mod` declares `go 1.26`
- Driver build: `go build ./cmd/driver`
- Driver tests: `go test ./...` (table tests in `internal/realtime/`)
- The Dockerfile uses `golang:1.26` as the build image

## What to do

Add Go 1.26 installation to `omp-sandbox/container/sandbox.containerfile`.

### Option A: Download from go.dev (recommended)

```dockerfile
ARG GO_VERSION=1.26.0
ARG GO_SHA256=<verify at download time>
RUN curl -fsSL -o /tmp/go.tar.gz \
        "https://go.dev/dl/go${GO_VERSION}.linux-arm64.tar.gz" \
    && echo "${GO_SHA256}  /tmp/go.tar.gz" | sha256sum --check \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && ln -s /usr/local/go/bin/go /usr/local/bin/go \
    && ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt \
    && rm -f /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"
```

### Option B: Fedora package

```dockerfile
RUN dnf --assumeyes install golang && dnf clean all
```

Fedora 42 ships Go 1.24, which may not satisfy `go 1.26` in `go.mod`.
Option A is preferred for version control.

## Acceptance

```bash
go version  # prints go version go1.26...
cd /workspace/veronica/app/driver && go test ./...
```
