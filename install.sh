#!/usr/bin/env bash
# Kobler sbx-oppsettet inn på verten: fish-integrasjon (abbr, completion, PATH).
set -euo pipefail

SBX_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

for cmd in sbx jq git python3; do
  command -v "$cmd" >/dev/null || echo "advarsel: fant ikke '$cmd' i PATH" >&2
done

chmod +x "$SBX_DIR"/bin/* "$SBX_DIR"/init/*.sh "$SBX_DIR"/hooks/*.sh

FISH_CONF="$HOME/.config/fish/conf.d"
mkdir -p "$FISH_CONF"
ln -sfn "$SBX_DIR/fish/sbx.fish" "$FISH_CONF/sbx.fish"
echo "Lenket $FISH_CONF/sbx.fish -> $SBX_DIR/fish/sbx.fish"

cat <<EOF

Ferdig. Åpne et nytt fish-skall (eller: source $FISH_CONF/sbx.fish).
Bruker du ikke fish, legg til i PATH:  export PATH="$SBX_DIR/bin:\$PATH"

Neste steg:
  sbx secret set github     # GitHub-token (se README)
  sbx-github-policy         # begrens skrivekall mot GitHub (policy/github-hviteliste.txt)
  sbx-bygg-base             # bygg base-template
  sbx-copilot <katalog>     # start copilot i en sandkasse
  sbx-shell <katalog>       # fish i samme sandkasse
  sbx-vscode <katalog>      # VS Code (Remote - SSH) mot samme sandkasse
EOF
