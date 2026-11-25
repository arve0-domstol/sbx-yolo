#!/usr/bin/env bash
# Kjøres som agent-bruker inne i byggesandkassen: dotfiles og global git-konfig.
# Idempotent – trygt å kjøre flere ganger.
set -euo pipefail

INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Kopierer dotfiles til $HOME"
cp -R "$INIT_DIR/files/." "$HOME/"

echo "==> Git-konfig"
GITCONFIG="$HOME/.config/git/config"
[ -n "${GIT_USER_NAME:-}" ] && git config --file "$GITCONFIG" user.name "$GIT_USER_NAME"
[ -n "${GIT_USER_EMAIL:-}" ] && git config --file "$GITCONFIG" user.email "$GIT_USER_EMAIL"

echo "dotfiles.sh ferdig"
