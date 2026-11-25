#!/usr/bin/env bash
# Globale nettverksregler (gjelder alle sandkasser). Regler er idempotente –
# finnes de allerede, rapporterer sbx "Already covered".
set -euo pipefail

# Verter som trengs for mise-verktøyene i init/files/.config/mise/config.toml,
# og som ikke dekkes av standard-policyen. Sjekk `sbx policy log` ved feil.
ALLOW_HOSTS=(
  mise.jdx.dev
  mise-java.jdx.dev
  go.dev
  download.java.net
  api.adoptium.net
)

for host in "${ALLOW_HOSTS[@]}"; do
  sbx policy allow network "$host"
done

# Skrivekall mot GitHub begrenses til hvitelisten i policy/github-hviteliste.txt.
"$SBX_DIR/bin/sbx-github-policy"

# Push er tillatt i hvitelisten; sbx-copilot/sbx-shell --ingen-push blokkerer per sandkasse.
# En global deny-regel kan ikke overstyres per sandkasse, så den er av som standard.
if [ "${SBX_GLOBAL_DENY_PUSH:-0}" = 1 ]; then
  sbx policy deny network github.com --method POST --path '/**/git-receive-pack'
fi
