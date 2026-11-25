#!/usr/bin/env bash
# Kjøres som agent-bruker inne i byggesandkassen: dotfiles, mise og global konfig.
# Idempotent – trygt å kjøre flere ganger.
set -euo pipefail

INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISE="$HOME/.local/bin/mise"

echo "==> Kopierer dotfiles til $HOME"
cp -R "$INIT_DIR/files/." "$HOME/"

echo "==> Installerer mise"
if [ ! -x "$MISE" ]; then
  curl -fsSL https://mise.run | sh
fi
"$MISE" --version

echo "==> mise install"
"$MISE" trust --all --yes "$HOME/.config/mise/config.toml" >/dev/null 2>&1 || true
"$MISE" install --yes
"$MISE" reshim

# Bash leser /etc/sandbox-persistent.sh for alle skall (også ikke-interaktive via
# BASH_ENV), så agentens kommandoer finner mise-verktøyene via shims.
PERSISTENT=/etc/sandbox-persistent.sh
MARKER='# sbx: mise'
if [ -w "$PERSISTENT" ] && ! grep -qF "$MARKER" "$PERSISTENT"; then
  cat >> "$PERSISTENT" <<'EOF'
# sbx: mise
export PATH="$HOME/.local/share/mise/shims:$PATH"
EOF
fi

echo "==> Git-konfig"
GITCONFIG="$HOME/.config/git/config"
[ -n "${GIT_USER_NAME:-}" ] && git config --file "$GITCONFIG" user.name "$GIT_USER_NAME"
[ -n "${GIT_USER_EMAIL:-}" ] && git config --file "$GITCONFIG" user.email "$GIT_USER_EMAIL"

echo "==> Verktøy i base:"
"$MISE" ls --current || true
echo "user.sh ferdig"
