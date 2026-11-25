# Sandkasse-variant av vertens ~/.config/fish/config.fish
# (uten macOS-stier, zoxide/starship og hemmeligheter).

# VS Code Remote-SSH sender et sh-skript på stdin og holder stdin åpen. Fish
# leser hele stdin før noe kjøres, så tilkoblingen henger. Slike økter (login,
# ikke-interaktiv, uten -c og uten TTY) overlates til bash.
if status is-login; and not status is-interactive; and not isatty stdin
    and not contains -- -c (string split0 </proc/$fish_pid/cmdline 2>/dev/null)
    exec bash
end

set -g fish_greeting

fish_add_path -g ~/.local/bin

# copilot i yolo-modus (se functions/copilot.fish). Stoler også på arbeidskatalogen.
set -gx COPILOT_ALLOW_ALL true

# rg defaults
if test -f ~/.ripgreprc
    set -gx RIPGREP_CONFIG_PATH ~/.ripgreprc
end

# mise: activate i interaktive skall, shims ellers (f.eks. fish -c)
if test -x ~/.local/bin/mise
    if status is-interactive
        ~/.local/bin/mise activate fish | source
    else
        fish_add_path -g ~/.local/share/mise/shims
    end
end
