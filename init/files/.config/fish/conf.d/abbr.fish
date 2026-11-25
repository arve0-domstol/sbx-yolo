# Abbr hentet fra vertens ~/.config/fish/config.fish

# git short hands
abbr g git
abbr --add --command git ch checkout
abbr --add --command git s status
abbr --add --command git a add
abbr --add --command git aa "add --all"
abbr --add --command git unstage "reset HEAD --"
abbr --add --command git d diff
abbr --add --command git ds "diff --staged"
abbr --add c --command git --set-cursor "commit -m '%"
abbr --add --command git p push
abbr --add --command git pf "push --force-with-lease"
abbr --add --command git pl pull
abbr --add --command git l log -8 --oneline --graph --decorate
abbr --add --command git ll log --oneline --graph --decorate
abbr --add --command git amend "commit --amend --no-edit"
abbr --add --command git b branch

# gh short hands
abbr pr "gh pr create"
