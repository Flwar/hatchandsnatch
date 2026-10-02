#!/usr/bin/env sh
# Runs every automated check: formatting, lint, a full Rojo build and the Lune tests.
# Usage (from the repo root):  sh tools/check.sh
set -e

echo "== StyLua (formatting)"
stylua --check src tests tools/preview/*.luau

echo "== Selene (lint)"
if [ ! -f roblox.yml ]; then
	selene generate-roblox-std
fi
selene src

echo "== Rojo (build)"
mkdir -p build
rojo build default.project.json -o build/HatchAndSnatch.rbxl

echo "== Lune (tests)"
lune run tests/run.luau

echo "All checks passed."
