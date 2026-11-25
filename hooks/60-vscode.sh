#!/usr/bin/env bash
# Forhåndsinstallerer VS Code Server (Remote - SSH) i base for samme versjon som
# VS Code på verten, slik at sbx-vscode kobler til uten nedlasting. Oppdateres
# VS Code på verten, lastes ny server ned ved første tilkobling (eller bygg på nytt).
# Neste linje gjør at sbx-bygg-base kjører hooken på nytt når VS Code-versjonen endres.
# sbx-nøkkel: code --version | sed -n 2p
set -euo pipefail

B="$SBX_BUILD_NAME"

if ! command -v code >/dev/null; then
  echo "Fant ikke 'code' på verten – hopper over VS Code Server"
  exit 0
fi

COMMIT="$(code --version | sed -n 2p)"
if ! [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Fant ikke commit i 'code --version' – hopper over VS Code Server"
  exit 0
fi

echo "Installerer VS Code Server $COMMIT"
sbx exec -i -e "COMMIT=$COMMIT" "$B" bash -s <<'EOF'
set -euo pipefail
case "$(uname -m)" in
  aarch64) ARCH=arm64 ;;
  x86_64) ARCH=x64 ;;
  *) echo "Ukjent arkitektur $(uname -m) – hopper over"; exit 0 ;;
esac

D="$HOME/.vscode-server"
S="$D/cli/servers/Stable-$COMMIT/server"
URL="https://update.code.visualstudio.com/commit:$COMMIT"

if [ -x "$D/code-$COMMIT" ] && [ -x "$S/bin/code-server" ]; then
  echo "Finnes allerede"
  exit 0
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
curl -fsSL "$URL/cli-alpine-$ARCH/stable" | tar -xz -C "$T"
install -D -m 755 "$T/code" "$D/code-$COMMIT"
mkdir -p "$S"
curl -fsSL "$URL/server-linux-$ARCH/stable" | tar -xz -C "$S" --strip-components=1
"$S/bin/code-server" --version | head -2
EOF
