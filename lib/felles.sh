# shellcheck shell=bash
# Felles oppsett for bin/-scriptene. Sources, kjøres ikke direkte.

SBX_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
export SBX_DIR

set -a
# shellcheck source=../config.env
source "$SBX_DIR/config.env"
if [ -f "$SBX_DIR/config.local.env" ]; then
  # shellcheck disable=SC1091
  source "$SBX_DIR/config.local.env"
fi
set +a

info() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
advarsel() { printf '\033[1;33madvarsel:\033[0m %s\n' "$*" >&2; }
feil() { printf '\033[1;31mfeil:\033[0m %s\n' "$*" >&2; exit 1; }

sandkasse_finnes() {
  sbx ls -q 2>/dev/null | grep -qx -- "$1"
}

# Sant hvis template-referansen (f.eks. sbx-base:latest) finnes lokalt.
template_finnes() {
  local repo="${1%:*}" tag="${1##*:}"
  [ "$repo" = "$1" ] && tag=latest
  sbx template ls -q 2>/dev/null | grep -Fqx -e "${repo}:${tag}" -e "docker.io/library/${repo}:${tag}"
}
