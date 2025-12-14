#!/usr/bin/env bash
set -euo pipefail

tofu init -backend-config=backend.dev.hcl "$@"
