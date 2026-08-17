# dsh-tui — see README.md. The runtime wheel in .venv is platform-specific
# (this checkout: macos-arm64); the sandbox image builds its own linux one.
.PHONY: build test golden setup demo

build:
	go build -o dsh-tui ./cmd/dsh-tui

test: build
	go vet ./...
	go test ./...
	bash scripts/golden.bash

golden:
	UPDATE=1 bash scripts/golden.bash

setup:
	uv venv .venv && uv pip install --python .venv/bin/python deepseek-harness-sdk pillow

demo: build
	DSH_REPLAY_FAST=1 ./dsh-tui -replay testdata/demo.ndjson
