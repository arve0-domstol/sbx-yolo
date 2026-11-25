#!/usr/bin/env bash
# Mal for egne kommandoer mot byggesandkassen. Kjøres på verten etter init/*.sh
# og før template-en lagres. $SBX_BUILD_NAME og alle variabler fra config.env
# er tilgjengelige.
set -euo pipefail

B="$SBX_BUILD_NAME"

# Eksempler:
# sbx exec -u root "$B" bash -c 'apt-get update && apt-get install -y postgresql-client && rm -rf /var/lib/apt/lists/*'
# sbx exec "$B" bash -lc 'mise use -g node@lts'
# sbx cp "$HOME/.ripgreprc" "$B:/home/agent/.ripgreprc"
# sbx exec "$B" bash -c 'npm install -g some-cli'

: "${B:?}"
