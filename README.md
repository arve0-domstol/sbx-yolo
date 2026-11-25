# sbx – gjenbrukbart oppsett for Docker Sandboxes

Bygger en lokal **base-template** for [Docker Sandboxes (`sbx`)](https://docs.docker.com/ai/sandboxes/)
med fish, mise-verktøy og global konfigurasjon ferdig installert, og starter nye sandkasser for
et git-repo fra denne på sekunder. Skills, GitHub-token og nettverkspolicy holdes på verten.

Detaljer om hvordan alt henger sammen, designvalg og åpne spørsmål står i [SPEC.md](SPEC.md).
Risikoer ved å kjøre agenter i yolo-modus, og hvordan de begrenses, står i [SIKKERHET.md](SIKKERHET.md).

> Testet med `sbx v0.54.1` på macOS (Apple Silicon) og agenten `copilot`.

## Installasjon

Krav: [`sbx`](https://docs.docker.com/ai/sandboxes/), `git`, `jq`, `python3` og bash. Fish anbefales.

`jq` og `python3` ligger i [mise.toml](mise.toml). `sbx` finnes ikke i mise, så på macOS
(Apple Silicon, Sonoma 14+) installeres det med Homebrew:

```sh
brew trust docker/tap
brew install docker/tap/sbx
sbx login
```

```sh
git clone <dette-repoet> ~/git/sbx
cd ~/git/sbx
mise trust && mise install
./install.sh
```

`mise.toml` gjelder bare inne i repoet. Scriptene i `bin/` kjøres fra andre kataloger, så
mangler `jq` eller `python3` globalt, installer dem globalt med `mise use -g jq python`.

`install.sh` gjør scriptene kjørbare og lenker [fish/sbx.fish](fish/sbx.fish) til
`~/.config/fish/conf.d/sbx.fish`. Det legger `bin/` i `PATH` og gir abbr og completion.
Bruker du ikke fish, legg `bin/` i `PATH` selv:

```sh
export PATH="$HOME/git/sbx/bin:$PATH"
```

Lagre GitHub-token som secret på verten (tokenet havner aldri i sandkassen):

```sh
sbx secret set github                              # lim inn fin-granulert PAT (anbefalt, se SIKKERHET.md)
sbx secret set github --command 'gh auth token'    # eller: gjenbruk gh på verten (mye bredere tilgang)
```

Begrens hvilke skrivekall sandkassene kan gjøre mot GitHub (se
[GitHub-hviteliste](#sbx-github-policy--hviteliste-for-skrivekall-mot-github)):

```sh
sbx-github-policy
```

Bygg base-template-en:

```sh
sbx-bygg-base
```

## Bruk

### `sbx-copilot` og `sbx-shell` – copilot eller fish i sandkassen for et git-repo

```
sbx-copilot [katalog] [--navn NAVN] [--mount] [--ingen-push] [--base TEMPLATE] [-- agent-argumenter]
sbx-shell   [katalog] [--navn NAVN] [--mount] [--ingen-push] [--base TEMPLATE] [-- kommando]
```

Kommandoene tar de samme argumentene og bruker **samme sandkasse** for en katalog
(`copilot-<katalognavn>`). Den som kjøres først, oppretter sandkassen fra `sbx-base:latest`.
`sbx-copilot` starter agenten, mens `sbx-shell` åpner fish i repoet. Har du copilot i én
fane, kan du derfor åpne et skall i samme sandkasse med `sbx-shell` i en annen fane.

```sh
sbx-copilot .                          # copilot i copilot-<katalognavn>
sbx-shell .                            # fish i samme sandkasse
sbx-shell . -- go test ./...           # kjør én kommando i stedet for fish
sbx-copilot ~/git/app --navn app-fix   # eget navn
sbx-copilot . --mount                  # monter repoet direkte i stedet for privat klone
sbx-copilot . --ingen-push             # blokker git push til github.com
sbx-copilot . --base sbx-base:20261125-1055   # rull tilbake til en eldre base
sbx-copilot . -- --continue            # argumenter videre til agenten
```

- Finnes sandkassen fra før, brukes den. `--mount`, `--ingen-push` og `--base` gjelder bare
  når sandkassen opprettes.
- Som standard jobber agenten på en **privat klone** av repoet (`sbx create --clone`), slik
  at den ikke kan endre filer på verten. Klonen har samme sti og `origin` som repoet ditt,
  men bare commits blir med, ikke ucommittede endringer. Hent agentens commits på verten med
  `git fetch sandbox-<navn>`. `--mount` monterer repoet direkte i stedet (se
  [SIKKERHET.md](SIKKERHET.md)).
- Copilot starter alltid i yolo-modus (alle verktøy godkjent, workspace er klarert), både
  via `sbx-copilot` og når du kjører `copilot` i fish fra `sbx-shell`. Sandkassen og
  nettverkspolicyen er sikkerhetsgrensen.
- Inne i copilot kan du kjøre enkeltkommandoer med `!`, f.eks. `!git status`.
- Agenten kan pushe til GitHub og lage/kommentere PR selv (krever at tokenet har
  skrivetilgang), begrenset av [hvitelisten](policy/github-hviteliste.txt). `--ingen-push`
  blokkerer i tillegg `git push` over HTTPS til github.com for sandkassen.

> **Sikkerhet:** copilot kjører uten å spørre, og kan gjøre alt GitHub-tokenet og
> nettverkspolicyen tillater. Bruk et fin-granulert token begrenset til egne repo og uten
> Workflows-rettighet, og vær forsiktig med `--mount`. Se [SIKKERHET.md](SIKKERHET.md).

### `sbx-vscode` – VS Code mot sandkassen over SSH

```
sbx-vscode [katalog] [--navn NAVN] [--mount] [--ingen-push] [--base TEMPLATE] [-- code-argumenter]
```

Åpner VS Code med Remote - SSH i workspace-katalogen til **samme sandkasse** som
`sbx-copilot`/`sbx-shell`. Sandkassen opprettes eller startes ved behov.

```sh
sbx-vscode .                           # VS Code mot copilot-<katalognavn>
sbx-vscode . -- --new-window           # argumenter videre til code
```

Krav på verten: VS Code med `code` i `PATH` («Shell Command: Install 'code' command in PATH») og
utvidelsen [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh).

Slik fungerer det:

- SSH går gjennom sbx sin innebygde SSH-støtte (eksperimentell). `sbx setup ssh` legger en
  `Include` i `~/.ssh/config` for `Host *.sbx` med `ProxyCommand sbx ssh proxy`. `sbx-vscode`
  kjører den automatisk hvis den mangler. Det trengs ingen sshd, nøkler eller publiserte porter
  i sandkassen. Sandkassen nås som `<navn>.sbx`, f.eks. `ssh copilot-app.sbx` eller
  `code --remote ssh-remote+copilot-app.sbx /sti/til/app`.
- VS Code Server for samme versjon som VS Code på verten bakes inn i base av
  [hooks/60-vscode.sh](hooks/60-vscode.sh). Oppdaterer du VS Code, lastes ny server ned ved
  første tilkobling, eller du kan kjøre `sbx-bygg-base` på nytt.
- Remote - SSH sender et sh-skript på stdin. Fish leser hele stdin før noe kjøres, så
  [config.fish](init/files/.config/fish/config.fish) i sandkassen sender slike økter
  (login, ikke-interaktiv, uten `-c` og uten TTY) videre til bash. Terminaler og
  `ssh <navn>.sbx` gir fortsatt fish.
- Sandkasser laget fra en eldre base mangler disse endringene. Bygg base på nytt og
  opprett sandkassen på nytt med `sbx rm <navn>`.

### `sbx-bygg-base` – bygg base-template

```
sbx-bygg-base [--behold] [--ingen-hooks]
```

Lager `sbx-base:<ÅÅÅÅMMDD-TTMM>` og `sbx-base:latest`, og beholder de tre siste dato-tagene.
Det tar et par minutter. Bygg på nytt når du endrer oppsettet eller vil ha oppdaterte pakker.

- `--behold` lar byggesandkassen `sbx-base-bygg` stå igjen etterpå.
- `--ingen-hooks` hopper over `hooks/*.sh`.
- Feiler bygget, står byggesandkassen igjen. Da kan du feilsøke med `sbx exec -it sbx-base-bygg fish`.

### `sbx-github-policy` – hviteliste for skrivekall mot GitHub

```
sbx-github-policy [--vis] [--fjern] [--fil FIL] [--sandbox NAVN]
```

All lesing mot GitHub er tillatt. Skrivekall (POST, PUT, PATCH, DELETE) til vertene i
[policy/github-hviteliste.txt](policy/github-hviteliste.txt) er bare tillatt hvis de står i
fila. Som standard kan agenten:

- `git fetch`/`clone`/`push` (og git lfs)
- lage PR, kommentere på PR/issues og svare på review-kommentarer
- bruke GraphQL (`gh` bruker det også til lesing, og det trengs for å resolve review-tråder)

Fila har kommenterte forslag til flere skrivetilganger. Ser du i `sbx policy log` at agenten
blir stoppet av noe den burde få lov til, legger du stien til i fila og kjører
`sbx-github-policy` igjen. Det gjelder umiddelbart for alle sandkasser, uten nytt bygg.

- `--vis` viser hvilke regler som legges til og fjernes, uten å endre noe.
- `--fjern` fjerner alle reglene igjen (åpner for alle skrivekall).
- `--sandbox NAVN` legger reglene på én sandkasse i stedet for globalt (nyttig for testing).
- Sjekk et enkelt kall med `sbx policy check http --method POST https://api.github.com/…`.

> sbx lar deny-regler vinne over allow-regler, og copilot-kitet tillater hele `api.github.com`.
> Scriptet oversetter derfor hvitelisten til deny-regler for alt annet (globale HTTP-deny-regler
> for `github.com` og `*.github.com` eies av scriptet). GraphQL-mutations kan ikke skilles fra
> queries på sti, så for GraphQL er det tokenets rettigheter som setter grensen. Bruk et
> fin-granulert token og branch protection.

### Abbr i fish

| Abbr  | Utvides til     | Eksempel        |
|-------|-----------------|-----------------|
| `sc`  | `sbx-copilot`   | `sc .`          |
| `ss`  | `sbx-shell`     | `ss .`          |
| `sv`  | `sbx-vscode`    | `sv .`          |
| `snb` | `sbx-bygg-base` | `snb`           |
| `sl`  | `sbx ls`        | `sl`            |
| `sx`  | `sbx exec -it`  | `sx <navn> fish`|
| `srm` | `sbx rm`        | `srm <navn>`    |

Completion finnes for kataloger, sandkassenavn (`--navn`) og templates (`--base`).

### Nyttige `sbx`-kommandoer

```sh
sbx ls                       # sandkasser
sbx template ls              # templates (sbx-base:*)
sbx exec -it <navn> fish     # skall i en sandkasse
sbx policy log               # se blokkerte nettverkskall
sbx skills ls                # skills som deles med sandkassene
```

## Tilpasse oppsettet

Etter endringer i `init/` eller `hooks/` kjører du `sbx-bygg-base` på nytt. Endringer i
skills, secrets og policy gjelder uten nytt bygg.

| Hva                         | Hvor |
|-----------------------------|------|
| Agent, navn, minne, CPU, git-navn/e-post, antall tags | [config.env](config.env), eller `config.local.env` for lokale overstyringer (ikke versjonert) |
| apt-pakker                  | [init/root.sh](init/root.sh) eller `SBX_APT_EXTRA` i `config.env` |
| mise-verktøy (go, java, python, …) | [init/files/.config/mise/config.toml](init/files/.config/mise/config.toml) |
| fish-konfig og abbr i sandkassen | [init/files/.config/fish/](init/files/.config/fish/) |
| global git-konfig           | [init/files/.config/git/config](init/files/.config/git/config) |
| andre filer i `$HOME`       | legg dem i [init/files/](init/files/). Alt der kopieres til `/home/agent` |
| skills                      | [hooks/10-skills.sh](hooks/10-skills.sh): `SKILL_REPOS` for git-repo. Lokale skills importeres automatisk |
| nettverksregler             | [hooks/20-policy.sh](hooks/20-policy.sh): `ALLOW_HOSTS`. `SBX_GLOBAL_DENY_PUSH=1` gir global push-blokkering |
| skrivetilgang mot GitHub    | [policy/github-hviteliste.txt](policy/github-hviteliste.txt), deretter `sbx-github-policy` (ikke nytt bygg) |
| VS Code Server i base       | [hooks/60-vscode.sh](hooks/60-vscode.sh) (hoppes over hvis `code` mangler på verten) |
| egne kommandoer i base      | [hooks/90-ekstra.sh](hooks/90-ekstra.sh), eller nye `hooks/NN-navn.sh` |

Hooks kjøres **på verten** i alfabetisk rekkefølge. `SBX_BUILD_NAME` og variablene fra
`config.env` er tilgjengelige. Hooks med nummer `00–49` kjøres *før* init-scriptene
(f.eks. policy som må være på plass før `mise install`), og `50–99` kjøres *etter*.

Feiler `mise install` eller `apt-get` på grunn av nettverk, finner du verten med `sbx policy log`.
Legg den til i `ALLOW_HOSTS` og bygg på nytt.

## Struktur

```
bin/sbx-bygg-base   bygger base-template
bin/sbx-copilot     copilot i sandkasse for en git-katalog (oppretter ved behov)
bin/sbx-shell       fish/kommando i samme sandkasse
bin/sbx-vscode      VS Code (Remote - SSH) mot samme sandkasse
bin/sbx-github-policy  synkroniserer GitHub-hvitelisten til sbx policy
policy/             hviteliste for skrivekall mot GitHub
lib/felles.sh       laster config og felles hjelpefunksjoner
lib/sandkasse.sh    felles argumenter, navngiving og oppretting for sbx-copilot/sbx-shell
init/               kopieres inn i byggesandkassen (root.sh, user.sh, files/)
hooks/              kjøres på verten under bygging
fish/sbx.fish       fish-integrasjon for verten
config.env          felles variabler
install.sh          installasjon på verten
SIKKERHET.md        risikoer og anbefalinger for yolo-modus
```

Hvordan bygget fungerer steg for steg, hvordan GitHub-tilgang og policy er tenkt, og hva som
er verifisert, står i [SPEC.md](SPEC.md).
