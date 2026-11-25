# sbx – vert-integrasjon for fish.
# Installeres med: ln -s (pwd)/fish/sbx.fish ~/.config/fish/conf.d/sbx.fish

set -l __sbx_dir (path resolve (status filename) | path dirname | path dirname)
fish_add_path -g $__sbx_dir/bin

if status is-interactive
    abbr -a sc sbx-copilot
    abbr -a ss sbx-shell
    abbr -a sv sbx-vscode
    abbr -a snb sbx-bygg-base
    abbr -a sl 'sbx ls'
    abbr -a sx 'sbx exec -it' # sx <navn> fish
    abbr -a srm 'sbx rm'
end

function __sbx_sandkasser
    sbx ls -q 2>/dev/null
end

function __sbx_templates
    sbx template ls -q 2>/dev/null | string replace -r '^docker\.io/library/' ''
end

# sbx sin egen completion (subkommandoer, flagg og sandkassenavn)
if not complete -c sbx | string length -q
    sbx completion fish 2>/dev/null | source
end

for cmd in sbx-copilot sbx-shell sbx-vscode
    complete -c $cmd -f
    complete -c $cmd -n 'not __fish_seen_argument -- --' -a '(__fish_complete_directories)'
    complete -c $cmd -l navn -x -a '(__sbx_sandkasser)' -d 'Navn på sandkassen'
    complete -c $cmd -l mount -d 'Monter katalogen direkte i stedet for privat klone'
    complete -c $cmd -l ingen-push -d 'Blokker git push til github.com'
    complete -c $cmd -l base -x -a '(__sbx_templates)' -d 'Template å starte fra'
    complete -c $cmd -s h -l help -d 'Vis hjelp'
end

complete -c sbx-bygg-base -f
complete -c sbx-bygg-base -l full -d 'Bygg fra bunnen av'
complete -c sbx-bygg-base -l tving -d 'Kjør alle steg på nytt oppå latest'
complete -c sbx-bygg-base -l behold -d 'La byggesandkassen stå igjen'
complete -c sbx-bygg-base -l ingen-hooks -d 'Hopp over hooks/*.sh'
complete -c sbx-bygg-base -s h -l help -d 'Vis hjelp'

complete -c sbx-github-policy -f
complete -c sbx-github-policy -l fil -r -F -d 'Hviteliste (standard: policy/github-hviteliste.txt)'
complete -c sbx-github-policy -l vis -d 'Vis endringene uten å gjøre dem'
complete -c sbx-github-policy -l fjern -d 'Fjern alle styrte regler'
complete -c sbx-github-policy -l sandbox -x -a '(__sbx_sandkasser)' -d 'Kun for én sandkasse'
complete -c sbx-github-policy -s h -l help -d 'Vis hjelp'
