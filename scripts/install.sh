#!/usr/bin/env bash
#
# install.sh — Install the sandbox CLI on macOS/Linux by cloning the repo and
# building it from source (no prebuilt release required).
#
# This differs from cli/bin/install.sh, which downloads a prebuilt binary from
# a published GitHub release. This one clones a branch and compiles it with Bun.
#
# Quick start:
#   curl -fsSL https://raw.githubusercontent.com/benlavalley/sandbox/windows-support/scripts/install.sh | bash
#
# Env overrides:
#   SANDBOX_REPO=benlavalley/sandbox          # source repo
#   SANDBOX_BRANCH=windows-support    # branch/tag to build
#   PREFIX=/usr/local/bin                     # install dir (must be on PATH)
set -euo pipefail

REPO="${SANDBOX_REPO:-benlavalley/sandbox}"
BRANCH="${SANDBOX_BRANCH:-windows-support}"

if [ -n "${PREFIX:-}" ]; then
  INSTALL_DIR="$PREFIX"
elif [ -w "/usr/local/bin" ]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="$HOME/.local/bin"
fi
mkdir -p "$INSTALL_DIR"

command -v git >/dev/null 2>&1 || { echo "error: git is required"; exit 1; }

if ! command -v bun >/dev/null 2>&1; then
  echo "==> Installing bun"
  curl -fsSL https://bun.sh/install | bash
  export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
  export PATH="$BUN_INSTALL/bin:$PATH"
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Cloning $REPO@$BRANCH"
git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$WORKDIR/sandbox"

cd "$WORKDIR/sandbox/cli"
echo "==> Installing dependencies"
bun install --frozen-lockfile

echo "==> Building sandbox (host target)"
bun build --compile src/index.ts --outfile sandbox

if [ "$(uname -s)" = "Darwin" ] && command -v codesign >/dev/null 2>&1; then
  codesign --remove-signature sandbox 2>/dev/null || true
  codesign --force --deep -s - sandbox
fi

install -m 0755 sandbox "$INSTALL_DIR/sandbox"

echo
echo "==> Installed: $INSTALL_DIR/sandbox"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) echo "    note: add $INSTALL_DIR to your PATH" ;;
esac
echo
echo "Start it (Docker must be running):"
echo "  sandbox serve"
