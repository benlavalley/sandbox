#!/usr/bin/env bash
#
# build.sh — Compile the sandbox CLI from source for every supported platform.
#
# Produces cli/dist/sandbox-<os>-<arch>.tar.gz for:
#   macOS arm64/x64, Linux x64/arm64, Windows x64
#
# Bun cross-compiles all targets from any host, so this can run on a single
# machine. macOS binaries are ad-hoc codesigned (only possible when run on
# macOS — on other hosts the darwin artifacts are produced unsigned).
#
# Usage: scripts/build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/cli"
DIST="$CLI/dist"

command -v bun >/dev/null 2>&1 || { echo "error: bun is required (https://bun.sh)"; exit 1; }

cd "$CLI"
echo "==> Installing dependencies"
bun install --frozen-lockfile

rm -rf "$DIST"
mkdir -p "$DIST"

# bun_target : release-artifact-name : binary-filename
TARGETS=(
  "bun-darwin-arm64:sandbox-darwin-arm64:sandbox"
  "bun-darwin-x64:sandbox-darwin-amd64:sandbox"
  "bun-linux-x64:sandbox-linux-amd64:sandbox"
  "bun-linux-arm64:sandbox-linux-arm64:sandbox"
  "bun-windows-x64:sandbox-windows-amd64:sandbox.exe"
)

for entry in "${TARGETS[@]}"; do
  IFS=":" read -r target name binfile <<<"$entry"
  echo "==> Building $name ($target)"
  bun build --compile --target="$target" src/index.ts --outfile "$DIST/$binfile"

  case "$target" in
    bun-darwin-*)
      if command -v codesign >/dev/null 2>&1; then
        codesign --remove-signature "$DIST/$binfile" 2>/dev/null || true
        codesign --force --deep -s - "$DIST/$binfile"
      else
        echo "    note: codesign unavailable (not macOS) — $name left unsigned"
      fi
      ;;
  esac

  tar czf "$DIST/$name.tar.gz" -C "$DIST" "$binfile"
  rm -f "$DIST/$binfile"
  echo "    -> $DIST/$name.tar.gz"
done

echo "==> Done. Artifacts in $DIST:"
ls -lh "$DIST"/*.tar.gz
