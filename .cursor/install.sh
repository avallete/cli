#!/usr/bin/env bash
# Cloud Agent bootstrap for the Supabase CLI monorepo.
#
# Idempotent: safe to re-run against cached or partially prepared state. It
# provisions the pinned toolchains (via mise), the workspace dependencies (via
# pnpm), the reference submodules under .repos/, and the system libraries the
# cli-go keyring tests need. Runs after the repository is checked out.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. System packages
#    gnome-keyring + dbus back the Secret Service that
#    internal/utils/credentials/keyring_test.go talks to; libsecret is its
#    client library. CI provisions the same capability via unlock-keyring.
# ---------------------------------------------------------------------------
if ! command -v gnome-keyring-daemon >/dev/null 2>&1 || ! command -v dbus-run-session >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    log "Installing system packages (gnome-keyring, dbus, libsecret)"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      gnome-keyring dbus dbus-x11 libsecret-1-0
  else
    echo "WARN: apt-get/sudo unavailable; skipping keyring system packages (cli-go keyring test will be skipped)."
  fi
fi

# ---------------------------------------------------------------------------
# 2. mise (polyglot version manager) + pinned toolchains
#    Versions resolve from .bun-version, mise.toml, and package.json, so this
#    must run after checkout. mise is added to PATH for the rest of this script
#    and, for interactive shells, activated in ~/.bashrc.
# ---------------------------------------------------------------------------
export MISE_INSTALL_PATH="$HOME/.local/bin/mise"
if ! [ -x "$MISE_INSTALL_PATH" ]; then
  log "Installing mise"
  curl -fsSL https://mise.run | sh
fi
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# Persist activation for interactive shells (idempotent via marker guard).
if ! grep -q 'mise activate bash # cursor-cloud' "$HOME/.bashrc" 2>/dev/null; then
  log "Activating mise in ~/.bashrc"
  cat >> "$HOME/.bashrc" <<'BASHRC'

# Supabase CLI toolchains (managed by mise) — added by .cursor/install.sh
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash)" # cursor-cloud
fi
BASHRC
fi

log "Installing pinned toolchains (bun, node, pnpm, go, golangci-lint)"
mise trust --quiet "$REPO_ROOT/mise.toml"
mise trust --quiet "$REPO_ROOT"
mise install --yes

# Global defaults mirror the repo pins so the tools also resolve outside the
# repo tree (e.g. temp project dirs the CLI scaffolds and operates in).
mise use --global \
  bun@1.4.0 node@24.18.0 pnpm@11.4.0 go@1.26.5 golangci-lint@2.12.2 >/dev/null

# ---------------------------------------------------------------------------
# 3. Reference submodules (.repos/effect is the Effect v4 source of truth)
# ---------------------------------------------------------------------------
log "Initializing reference submodules (.repos/*)"
git submodule update --init --recursive

# ---------------------------------------------------------------------------
# 4. Workspace dependencies
# ---------------------------------------------------------------------------
log "Installing workspace dependencies (pnpm)"
pnpm install --frozen-lockfile

log "Environment ready."
