# shellcheck shell=bash disable=SC2034 # variablene brukes av bin/sbx-copilot og bin/sbx-shell
# Felles logikk for sbx-copilot og sbx-shell: argumenter, navngiving og oppretting
# av sandkasse fra base-template. Sources etter lib/felles.sh.

KATALOG=""
NAVN=""
MOUNT=0
INGEN_PUSH=0
BASE="$SBX_BASE_REPO:latest"
EKSTRA_ARGS=()

# Miljø for agent/skall i sandkassen. Gjelder også eksisterende sandkasser.
# COPILOT_ALLOW_ALL=true stoler på arbeidskatalogen (ingen "trust folder"-spørsmål)
# og godkjenner alle verktøy. sbx run starter i tillegg copilot med --yolo.
AGENT_ENV=(-e COPILOT_ALLOW_ALL=true)

felles_flagg_hjelp() {
  cat <<EOF
  --navn NAVN       navn på sandkassen (standard: $SBX_AGENT-<katalognavn>)
  --mount           monter katalogen direkte i stedet for å klone den (agenten
                    kan da endre filer på verten, se SIKKERHET.md)
  --ingen-push      blokker git push til github.com for denne sandkassen
  --base TEMPLATE   bruk en annen template, f.eks. $SBX_BASE_REPO:20250101-1200
  -h, --help        vis denne hjelpen

Som standard jobber agenten på en privat klone av repoet (kun commits, ikke
ucommittede endringer). Hent agentens commits på verten med
git fetch sandbox-<navn>. --mount, --ingen-push og --base gjelder bare når
sandkassen opprettes.
EOF
}

# Parser felles argumenter. Alt etter "--" havner i EKSTRA_ARGS.
les_argumenter() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --navn) [ $# -ge 2 ] || feil "--navn mangler verdi"; NAVN="$2"; shift ;;
      --navn=*) NAVN="${1#*=}" ;;
      --base) [ $# -ge 2 ] || feil "--base mangler verdi"; BASE="$2"; shift ;;
      --base=*) BASE="${1#*=}" ;;
      --mount) MOUNT=1 ;;
      --ingen-push) INGEN_PUSH=1 ;;
      -h|--help) bruk; exit 0 ;;
      --) shift; EKSTRA_ARGS=("$@"); break ;;
      -*) bruk >&2; feil "ukjent flagg: $1" ;;
      *)
        [ -z "$KATALOG" ] || feil "kun én katalog kan oppgis (fikk '$KATALOG' og '$1')"
        KATALOG="$1" ;;
    esac
    shift
  done

  KATALOG="${KATALOG:-.}"
  [ -d "$KATALOG" ] || feil "'$KATALOG' er ikke en katalog"
  KATALOG="$(cd "$KATALOG" && pwd -P)"
  git -C "$KATALOG" rev-parse --git-dir >/dev/null 2>&1 || feil "'$KATALOG' er ikke et git-repo"

  if [ -z "$NAVN" ]; then
    NAVN="$SBX_AGENT-$(basename "$KATALOG")"
    NAVN="$(printf '%s' "$NAVN" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-+//')"
    NAVN="$(printf '%s' "${NAVN:0:63}" | sed -E 's/-+$//')"
  fi
  [[ "$NAVN" =~ ^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$ ]] \
    || feil "ugyldig navn '$NAVN' (2–63 tegn, a-z, 0-9 og '-', kan ikke starte/slutte med '-')"
}

# Oppretter sandkassen fra base hvis den ikke finnes.
sikre_sandkasse() {
  if sandkasse_finnes "$NAVN"; then
    [ $MOUNT -eq 1 ] && advarsel "--mount ignoreres, $NAVN finnes allerede"
    [ $INGEN_PUSH -eq 1 ] && advarsel "--ingen-push ignoreres, $NAVN finnes allerede (se sbx policy ls $NAVN)"
    [ "$BASE" != "$SBX_BASE_REPO:latest" ] && advarsel "--base ignoreres, $NAVN finnes allerede"
    return 0
  fi

  template_finnes "$BASE" || feil "fant ikke template '$BASE'. Bygg den med: sbx-bygg-base"

  local args=(--pull never -t "$BASE" --name "$NAVN" --cpus "$SBX_CPUS" --memory "$SBX_MEMORY")
  if [ $MOUNT -eq 1 ]; then
    info "Oppretter $NAVN fra $BASE med $KATALOG montert (--mount)"
  else
    args+=(--clone)
    info "Oppretter $NAVN fra $BASE med en privat klone av $KATALOG"
    if [ -n "$(git -C "$KATALOG" status --porcelain 2>/dev/null)" ]; then
      advarsel "ucommittede endringer i $KATALOG blir ikke med i klonen"
    fi
    info "Hent agentens commits på verten med: git fetch sandbox-$NAVN"
  fi
  sbx create "${args[@]}" "$SBX_AGENT" "$KATALOG"

  if [ $INGEN_PUSH -eq 1 ]; then
    info "Blokkerer git push til github.com for $NAVN"
    sbx policy deny network --sandbox "$NAVN" github.com \
      --method POST --path '/**/git-receive-pack' >/dev/null
  fi
}
