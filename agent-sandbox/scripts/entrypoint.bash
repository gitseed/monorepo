#!/usr/bin/env bash
set -euo pipefail

default_model="openrouter/deepseek/deepseek-v4-flash"
model="${OMP_MODEL:-$default_model}"

exec agent-vault run -- omp --model "$model" "$@"
