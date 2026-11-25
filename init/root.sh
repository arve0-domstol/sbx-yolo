#!/usr/bin/env bash
# Kjøres som root inne i byggesandkassen: apt-pakker, fish og standard-shell.
# Idempotent – trygt å kjøre flere ganger.
set -euo pipefail

SBX_USER="${SBX_USER:-$(getent passwd 1000 | cut -d: -f1)}"
export DEBIAN_FRONTEND=noninteractive

PACKAGES=(
  fish
  ripgrep
  fd-find
  jq
  curl
  git
  unzip
  zip
  less
  ca-certificates
  build-essential
)
# shellcheck disable=SC2206
PACKAGES+=(${SBX_APT_EXTRA:-})

# Docker Hardened Images mangler /etc/shells, som får postinst for fish
# (add-shell) til å feile.
if [ ! -f /etc/shells ]; then
  rm -f /etc/shells.tmp
  printf '%s\n' /bin/sh /bin/bash /usr/bin/bash > /etc/shells
fi

apt-get update
apt-get install -y --no-install-recommends "${PACKAGES[@]}"
dpkg --configure -a

# Debian kaller binæren fdfind
if command -v fdfind >/dev/null && [ ! -e /usr/local/bin/fd ]; then
  ln -s "$(command -v fdfind)" /usr/local/bin/fd
fi

grep -qx /usr/bin/fish /etc/shells || echo /usr/bin/fish >> /etc/shells
chsh -s /usr/bin/fish "$SBX_USER"

apt-get clean
rm -rf /var/lib/apt/lists/*

echo "root.sh ferdig: $(getent passwd "$SBX_USER")"
