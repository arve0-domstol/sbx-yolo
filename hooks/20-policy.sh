#!/usr/bin/env bash
# Globale nettverksregler (gjelder alle sandkasser). Regler er idempotente –
# finnes de allerede, rapporterer sbx "Already covered".
set -euo pipefail

# Legg GitHub-begrensningene på plass før nettverk åpnes.
"$SBX_DIR/bin/sbx-github-policy"

# Push er tillatt i hvitelisten; sbx-copilot/sbx-shell --ingen-push blokkerer per sandkasse.
# En global deny-regel kan ikke overstyres per sandkasse, så den er av som standard.
if [ "${SBX_GLOBAL_DENY_PUSH:-0}" = 1 ]; then
  sbx policy deny network github.com --method POST --path '/**/git-receive-pack'
fi

# Tillat dokumentasjon, pakkeregistre og andre TCP-verter uten godkjenning.
# Eksplisitte deny-regler, inkludert GitHub-hvitelisten, gjelder fortsatt.
sbx policy allow network '**'
