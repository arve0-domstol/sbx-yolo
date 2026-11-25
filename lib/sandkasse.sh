# shellcheck shell=bash disable=SC2034 # variablene brukes av bin/sbx-copilot og bin/sbx-shell
# Felles logikk for sbx-copilot og sbx-shell: argumenter, navngiving og oppretting
# av sandkasse fra base-template. Sources etter lib/felles.sh.

KATALOG=""
# Hovedrepoet når KATALOG er en git-worktree (sbx --clone støtter ikke worktrees).
HOVEDREPO=""
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
  finn_worktree

  if [ -z "$NAVN" ]; then
    NAVN="$SBX_AGENT-$(basename "$KATALOG")"
    NAVN="$(printf '%s' "$NAVN" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-+//')"
    NAVN="$(printf '%s' "${NAVN:0:63}" | sed -E 's/-+$//')"
  fi
  [[ "$NAVN" =~ ^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$ ]] \
    || feil "ugyldig navn '$NAVN' (2–63 tegn, a-z, 0-9 og '-', kan ikke starte/slutte med '-')"
}

# Setter HOVEDREPO hvis KATALOG er en lenket git-worktree. Der er .git en fil som
# peker inn i hovedrepoets .git, så en klone av bare worktree-katalogen mangler
# objektene. Vi kloner derfor hovedrepoet og sjekker ut worktreens HEAD i sandkassen.
finn_worktree() {
  local git_dir felles_dir
  git_dir="$(git -C "$KATALOG" rev-parse --path-format=absolute --git-dir)"
  felles_dir="$(git -C "$KATALOG" rev-parse --path-format=absolute --git-common-dir)"
  [ "$git_dir" != "$felles_dir" ] || return 0

  [ "$(git -C "$felles_dir" rev-parse --is-bare-repository)" = false ] \
    || feil "'$KATALOG' er en worktree av et bart repo ($felles_dir), som ikke støttes"
  HOVEDREPO="$(git -C "$felles_dir/.." rev-parse --show-toplevel)"
}

# Sjekker ut worktreens gren (eller commit ved detached HEAD) i klonen av hovedrepoet.
sjekk_ut_worktree() {
  local commit gren remote merge
  commit="$(git -C "$KATALOG" rev-parse HEAD)"
  gren="$(git -C "$KATALOG" symbolic-ref -q --short HEAD || true)"
  if [ -n "$gren" ]; then
    remote="$(git -C "$KATALOG" config "branch.$gren.remote" || true)"
    merge="$(git -C "$KATALOG" config "branch.$gren.merge" || true)"
  fi
  info "Sjekker ut ${gren:-$commit} fra worktreen i klonen"
  # shellcheck disable=SC2016 # variablene ekspanderes i sandkassen
  sbx exec -e "REPO=$HOVEDREPO" -e "COMMIT=$commit" -e "GREN=$gren" \
    -e "REMOTE=${remote:-}" -e "MERGE=${merge:-}" "$NAVN" bash -c '
      set -euo pipefail
      cd "$REPO"
      git fetch -q --no-tags /run/sandbox/source "$COMMIT"
      if [ -z "$GREN" ]; then
        git checkout -q --detach "$COMMIT"
        exit 0
      fi
      git checkout -q -B "$GREN" "$COMMIT"
      if [ -n "$REMOTE" ] && [ -n "$MERGE" ] && git remote get-url "$REMOTE" >/dev/null 2>&1; then
        git config "branch.$GREN.remote" "$REMOTE"
        git config "branch.$GREN.merge" "$MERGE"
      fi
    ' || feil "klarte ikke å sjekke ut ${gren:-$commit} i $NAVN"
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
  local kilde="$KATALOG"
  if [ $MOUNT -eq 1 ]; then
    info "Oppretter $NAVN fra $BASE med $KATALOG montert (--mount)"
  else
    args+=(--clone)
    if [ -n "$HOVEDREPO" ]; then
      kilde="$HOVEDREPO"
      info "$KATALOG er en git-worktree; kloner hovedrepoet $HOVEDREPO i stedet"
    fi
    info "Oppretter $NAVN fra $BASE med en privat klone av $kilde"
    if [ -n "$(git -C "$KATALOG" status --porcelain 2>/dev/null)" ]; then
      advarsel "ucommittede endringer i $KATALOG blir ikke med i klonen"
    fi
    info "Hent agentens commits på verten med: git fetch sandbox-$NAVN"
  fi
  sbx create "${args[@]}" "$SBX_AGENT" "$kilde"

  if [ $MOUNT -eq 0 ] && [ -n "$HOVEDREPO" ]; then
    sjekk_ut_worktree
  fi

  if [ $INGEN_PUSH -eq 1 ]; then
    info "Blokkerer git push til github.com for $NAVN"
    sbx policy deny network --sandbox "$NAVN" github.com \
      --method POST --path '/**/git-receive-pack' >/dev/null
  fi
}
