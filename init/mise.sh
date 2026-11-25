#!/usr/bin/env bash
# Kjøres som agent-bruker inne i byggesandkassen: mise og globale verktøy.
# Idempotent – trygt å kjøre flere ganger.
set -euo pipefail

INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISE="$HOME/.local/bin/mise"

echo "==> Kopierer mise-konfig"
install -D -m 644 "$INIT_DIR/files/.config/mise/config.toml" "$HOME/.config/mise/config.toml"

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
  cat >> "$PERSISTENT" <<'EOS'
# sbx: mise
export PATH="$HOME/.local/share/mise/shims:$PATH"
EOS
fi

echo "==> Verktøy i base:"
"$MISE" ls --current || true
echo "mise.sh ferdig"
