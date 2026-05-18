#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$ROOT_DIR/dist"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "Building coder package..."
pip install anthropic boto3 --target "$DIST_DIR/coder_pkg" --quiet
cp -r "$ROOT_DIR/agents" "$DIST_DIR/coder_pkg/"
cp -r "$ROOT_DIR/tools" "$DIST_DIR/coder_pkg/"
cp -r "$ROOT_DIR/handlers" "$DIST_DIR/coder_pkg/"
cd "$DIST_DIR/coder_pkg" && zip -r "$DIST_DIR/coder.zip" . --quiet && cd "$ROOT_DIR"
echo "  dist/coder.zip ready"

echo "Building orchestrator package..."
pip install anthropic boto3 --target "$DIST_DIR/orchestrator_pkg" --quiet
cp -r "$ROOT_DIR/agents" "$DIST_DIR/orchestrator_pkg/"
cp -r "$ROOT_DIR/tools" "$DIST_DIR/orchestrator_pkg/"
cp -r "$ROOT_DIR/handlers" "$DIST_DIR/orchestrator_pkg/"
cd "$DIST_DIR/orchestrator_pkg" && zip -r "$DIST_DIR/orchestrator.zip" . --quiet && cd "$ROOT_DIR"
echo "  dist/orchestrator.zip ready"

echo "Build complete."
