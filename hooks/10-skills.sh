#!/usr/bin/env bash
# Skills holdes i sbx sin skills-store på verten og lenkes read-only inn i alle
# sandkasser ved oppstart – de bakes IKKE inn i template-en.
set -euo pipefail

# Skills fra git-repo: "<org>/<repo>" eller "<org>/<repo>:skill1,skill2"
SKILL_REPOS=(
  # anthropics/skills:frontend-design,pdf
)

echo "Importerer skills fra lokale agent-kataloger (~/.agents/skills, ~/.copilot/skills, …)"
sbx skills import --force

for kilde in "${SKILL_REPOS[@]+"${SKILL_REPOS[@]}"}"; do
  repo="${kilde%%:*}"
  if [ "$repo" != "$kilde" ]; then
    sbx skills add "$repo" --skill "${kilde#*:}" --force
  else
    sbx skills add "$repo" --force
  fi
done

if [ ${#SKILL_REPOS[@]} -gt 0 ]; then
  sbx skills update
fi

sbx skills ls
