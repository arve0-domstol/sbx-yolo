# sbx – gjenbrukbart oppsett for Docker Sandboxes

Et ferdig oppsett for [Docker Sandboxes (`sbx`)](https://docs.docker.com/ai/sandboxes/) som gir:

- en **base-VM** (lokal template) med mine verktøy, fish, mise og global konfigurasjon ferdig installert
- **rask oppstart** av nye sandkasser for et git-repo, basert på base-VM-en
- **skills**, **GitHub-token** og **nettverkspolicy** håndtert fra verten, ikke bakt inn i VM-en

Dokumentet er skrevet som en plan: seksjonene beskriver hva som skal bygges, og
[Implementeringsplan](#implementeringsplan) til slutt er sjekklisten. Se [README.md](README.md)
for installasjon og bruk.

> Testet mot `sbx v0.54.1` (macOS). `sbx skills` og `sbx kit` er eksperimentelle og kan endre seg.

---

## Oversikt

```
                 ┌──────────────────────────── vert (macOS) ────────────────────────────┐
                 │                                                                       │
 sbx-bygg-base ──► │ 1. sbx create --name sbx-base-bygg copilot        (uten workspace)    │
                 │ 2. sbx cp ./init  →  sandkasse:/tmp/init                              │
                 │ 3. sbx exec -u root … init/root.sh   (apt-pakker, fish)               │
                 │ 4. sbx exec        … init/user.sh    (mise, dotfiles, global config)  │
                 │ 5. hooks/*.sh på verten              (skills, policy, ekstra exec)    │
                 │ 6. sbx template save sbx-base-bygg sbx-base:<dato> (+ :latest)        │
                 │ 7. sbx rm sbx-base-bygg                                               │
                 │                                                                       │
 sbx-copilot ──► │ sbx create --pull never -t sbx-base:latest --name <navn> copilot <dir>│
 sbx-shell   ──► │ sbx run --name <navn>   /   sbx exec -it <navn> fish                  │
 sbx-vscode  ──► │ sbx setup ssh  +  code --remote ssh-remote+<navn>.sbx <workspace>     │
                 │                                                                       │
                 │ Delt på tvers av alle sandkasser (lever på verten):                   │
                 │   • sbx skills   – lenkes inn read-only ved oppstart                  │
                 │   • sbx secret   – GitHub-token injiseres av proxyen                  │
                 │   • sbx policy   – nettverks-/HTTP-regler                             │
                 └───────────────────────────────────────────────────────────────────────┘
```

**Prinsipp:** Alt som er *tregt å installere* (pakker, mise-verktøy, fish) bakes inn i
template-en. Alt som *endrer seg ofte eller er hemmelig* (skills, token, policy) holdes
på verten og kobles på ved oppstart.

---

## Katalogstruktur

```
sbx/
├── README.md
├── install.sh               # lenker fish/sbx.fish inn i ~/.config/fish/conf.d
├── bin/
│   ├── sbx-bygg-base        # bygger base-template
│   ├── sbx-copilot          # copilot i sandkasse for en git-katalog (oppretter ved behov)
│   ├── sbx-shell            # fish/kommando i samme sandkasse
│   ├── sbx-github-policy    # synkroniserer policy/github-hviteliste.txt til sbx policy
│   └── sbx-vscode           # VS Code (Remote - SSH) mot samme sandkasse
├── policy/
│   └── github-hviteliste.txt  # tillatte skrivekall mot GitHub
├── lib/
│   ├── felles.sh            # laster config.env (+ config.local.env) og hjelpefunksjoner
│   └── sandkasse.sh         # felles argumenter, navngiving og oppretting
├── init/                    # kopieres inn i sandkassen og kjøres der
│   ├── root.sh              # kjøres som root: apt, fish, chsh
│   ├── user.sh              # kjøres som agent-bruker: mise, dotfiles
│   └── files/               # filer som legges i $HOME
│       ├── .config/mise/config.toml       - standardverktøy som skal installeres globalt
│       ├── .config/fish/config.fish       - sandkasse-variant av lokal konfigurasjon
│       ├── .config/fish/conf.d/abbr.fish  - abbr fra vertens fish-konfig
│       ├── .config/fish/functions/copilot.fish - copilot alltid med --yolo
│       └── .config/git/config             - globale standarder, slik som push.autoSetupRemote=true og core.quotepath=false
├── hooks/                   # kjøres på VERTEN under sbx-bygg-base, i alfabetisk rekkefølge
│   ├── 10-skills.sh         #   00–49: før init-scriptene
│   ├── 20-policy.sh
│   ├── 60-vscode.sh         #   50–99: etter init-scriptene; VS Code Server for vertens VS Code-versjon
│   └── 90-ekstra.sh         #   vilkårlige `sbx exec`/`sbx cp`
├── fish/
│   └── sbx.fish             # abbr/completion for verten (sbx-copilot, sbx-shell, …)
└── config.env               # felles variabler (se under)
```

> Git-konfig legges i `~/.config/git/config` (XDG) og ikke `~/.gitconfig`, fordi sbx
> redigerer `~/.gitconfig` ved hver oppstart (`safe.directory`, `includeIf` for workspace).

`config.env`:

```sh
SBX_AGENT=copilot                 # agenten template-en lages for
SBX_BASE_REPO=sbx-base            # template-navn
SBX_BUILD_NAME=sbx-base-bygg      # midlertidig byggesandkasse
SBX_CPUS=0                        # 0 = auto
SBX_MEMORY=8g
SBX_KEEP_TAGS=3                   # antall dato-tags av base som beholdes
SBX_APT_EXTRA=""                  # ekstra apt-pakker
# brukes til å konfigurere git i base-template-en
GIT_USER_NAME="Arve Seljebu"
GIT_USER_EMAIL="arve.seljebu@domstol.no"
```

Lokale overstyringer kan legges i `config.local.env` (samme format), som leses etter `config.env`.

---

## Komponenter

### 1. Init-script (`init/`)

Kjøres **inne i** byggesandkassen. Må være idempotente (kan kjøres flere ganger).

**`init/root.sh`** (`sbx exec -u root`):
- copilot-imaget er *Docker Hardened Images (Debian 13)*, bruker `agent` (uid 1000), `$HOME=/home/agent`
- oppretter `/etc/shells` (mangler i imaget, og får fish sin postinst til å feile)
- `apt-get update && apt-get install -y fish ripgrep fd-find jq curl git build-essential …` (+ `fd` → `fdfind`)
- sett fish som standard-shell for agent-brukeren (`chsh -s /usr/bin/fish <bruker>`)
- rydd apt-cache for mindre template (`rm -rf /var/lib/apt/lists/*`)

**`init/user.sh`** (`sbx exec` som standardbruker):
- kopier `init/files/` til `$HOME` (fish-konfig, abbr, mise-konfig, git-konfig)
- installer mise: `curl https://mise.run | sh`
- aktiver mise i fish: `mise activate fish` i interaktive skall, shims i `PATH` ellers (`fish -c …`)
- aktiver mise i bash: shims legges i `PATH` via `/etc/sandbox-persistent.sh`, som leses av
  alle bash-skall (også ikke-interaktive, via `BASH_ENV`) – slik finner agenten verktøyene
- `mise install` – installerer alle verktøy fra `~/.config/mise/config.toml`
  (utgangspunkt: kopi av vertens [`~/.config/mise/config.toml`](/Users/arve.seljebu/.config/mise/config.toml))
- `trusted_config_paths = ["/"]` i mise-konfig, slik at prosjekt-`mise.toml` fungerer uten spørsmål
- global git-konfig (navn, e-post, `init.defaultBranch=main`, `pull.rebase=true`)

Fish-tilpasninger (`init/files/.config/fish/conf.d/abbr.fish`) hentes/velges fra
vertens [`~/.config/fish`](/Users/arve.seljebu/.config/fish) – bare det som gir mening i en sandkasse
(ingen macOS-spesifikke stier, ingen hemmeligheter).

### 2. `bin/sbx-bygg-base`

Bygger base-template-en fra bunnen av.

```
sbx-bygg-base [--behold] [--ingen-hooks]
```

Steg:

1. `source config.env` (+ `config.local.env`)
2. Fjern eventuell gammel byggesandkasse: `sbx rm -f $SBX_BUILD_NAME`
3. Opprett uten workspace-mount:
   `sbx create --name $SBX_BUILD_NAME --cpus $SBX_CPUS --memory $SBX_MEMORY $SBX_AGENT`
4. `sbx cp ./init $SBX_BUILD_NAME:/tmp/init`
5. Kjør `hooks/00–49*.sh` på verten (skills, policy) – policy må være på plass før `mise install`
6. `sbx exec -u root $SBX_BUILD_NAME bash /tmp/init/root.sh`
7. `sbx exec $SBX_BUILD_NAME bash /tmp/init/user.sh`
8. Kjør `hooks/50–99*.sh` på verten (ekstra kommandoer). Alle hooks får `SBX_BUILD_NAME` og
   variablene fra `config.env` eksportert
9. Rydd: `sbx exec $SBX_BUILD_NAME rm -rf /tmp/init ~/.cache/*`
10. Stopp: `sbx stop $SBX_BUILD_NAME` (`template save` krever stoppet sandkasse)
11. Lagre:
   `sbx template save $SBX_BUILD_NAME $SBX_BASE_REPO:$(date +%Y%m%d-%H%M)`
   og `sbx template save $SBX_BUILD_NAME $SBX_BASE_REPO:latest`
12. `sbx rm $SBX_BUILD_NAME` (med mindre `--behold`)
13. Rydd gamle dato-tags (behold `$SBX_KEEP_TAGS`) og skriv ut `sbx template ls`

Feilhåndtering: `set -euo pipefail`, og `trap` som lar byggesandkassen stå igjen ved feil
slik at man kan feilsøke med `sbx exec -it $SBX_BUILD_NAME fish`.

### 3. `bin/sbx-copilot` og `bin/sbx-shell`

Copilot eller fish i sandkassen for et git-repo. Begge bruker `lib/sandkasse.sh` og har
samme semantikk: samme argumenter, samme navn og dermed **samme sandkasse** for en katalog.
Den som kjøres først, oppretter sandkassen.

```
sbx-copilot [katalog] [--navn NAVN] [--mount] [--ingen-push] [--base TEMPLATE] [-- agent-argumenter]
sbx-shell   [katalog] [--navn NAVN] [--mount] [--ingen-push] [--base TEMPLATE] [-- kommando]
```

- valider at `<katalog>` er et git-repo (`git -C <katalog> rev-parse`)
- navn: `--navn` eller `<agent>-<basename av katalog>` (2–63 tegn, a-z, 0-9, `-`)
- hvis sandkassen ikke finnes, opprettes den først, slik at per-sandkasse-policy er på plass
  før agenten starter:
  ```sh
  sbx create --pull never -t "$SBX_BASE_REPO:latest" --name "$navn" --clone "$SBX_AGENT" "$katalog"  # uten --clone med --mount
  sbx policy deny network --sandbox "$navn" github.com --method POST --path '/**/git-receive-pack'  # kun med --ingen-push
  ```
- deretter:
  - `sbx-copilot`: `sbx run -e COPILOT_ALLOW_ALL=true --name "$navn" [-- agent-argumenter]`
  - `sbx-shell`: `sbx exec -it -e COPILOT_ALLOW_ALL=true "$navn" fish` (eller `-- kommando`).
    `sbx exec` starter i workspace-katalogen, både med klone og med `--mount`
- **yolo-modus**: `sbx run` starter allerede copilot med `--yolo`, men workspace monteres på
  vertens sti, som ikke er blant copilots klarerte mapper. `COPILOT_ALLOW_ALL=true` klarerer
  arbeidskatalogen, slik at copilot starter uten spørsmål. I fish legger
  `functions/copilot.fish` på `--yolo` (env-variabelen alene gir ikke Allow All i
  interaktive økter), og `config.fish` setter `COPILOT_ALLOW_ALL` også for `sbx exec … fish`.
- **privat klone som standard** (`sbx create --clone`): agenten kan ikke endre filer på
  verten (git-hooks, `mise.toml`, `.envrc` o.l. som ellers ville kjørt på verten senere).
  Klonen ligger på samme sti som på verten og har samme `origin`, så agenten pusher og
  lager PR som før. Bare commits blir med; `sikre_sandkasse` advarer hvis repoet har
  ucommittede endringer. Verten får remoten `sandbox-<navn>` (`git fetch sandbox-<navn>`).
  `--mount` monterer katalogen direkte (gammel oppførsel). Se [SIKKERHET.md](SIKKERHET.md).
- **git-worktree**: sbx `--clone` avviser worktrees (`.git` er en fil som peker inn i
  hovedrepoets `.git`, som ikke er montert). `finn_worktree` finner hovedrepoet, som klones
  i stedet, og `sjekk_ut_worktree` henter worktreens HEAD fra `/run/sandbox/source` med
  `git fetch <sha>` og sjekker ut samme gren (med upstream) eller detached commit.
  Navnet baseres fortsatt på worktree-katalogen. Worktrees av bare repo støttes ikke.
- feilmelding med hint om å kjøre `sbx-bygg-base` dersom `sbx-base:latest` mangler

### 3b. `bin/sbx-vscode`

Samme argumenter og sandkasse som `sbx-shell`, men åpner VS Code med Remote - SSH.

- SSH via sbx sin innebygde (eksperimentelle) SSH-støtte: `sbx setup ssh` skriver en
  generert config for `Host *.sbx` med `ProxyCommand sbx ssh proxy %n`, inkludert fra
  `~/.ssh/config`. Autentisering skjer via sandboxd (OS-bruker + Docker-innlogging), så
  sandkassen trenger verken sshd, nøkler eller publiserte porter. `sbx-vscode` kjører
  `sbx setup ssh` hvis `ssh -G <navn>.sbx` ikke viser sbx sin proxy.
- `sikre_sandkasse`, `sbx exec <navn> true` (start), workspace fra
  `sbx inspect --json` (`effective_working_dir`, riktig både med klone og `--mount`), deretter
  `code --remote ssh-remote+<navn>.sbx <workspace>`.
- **Fish som innloggingsskall:** sbx sin SSH-server starter brukerens skall (`fish -l`).
  Remote - SSH sender oppstartsskriptet på stdin og holder stdin åpen, men fish leser hele
  stdin før noe kjøres, så tilkoblingen ble tidsavbrutt. `config.fish` gjør derfor
  `exec bash` når skallet er login, ikke-interaktivt, uten `-c` og uten TTY. Å bytte
  innloggingsskall med `chsh` hjelper ikke, fordi sbx sin SSH-server ikke leser skallet fra `/etc/passwd`.
- **VS Code Server i base:** `hooks/60-vscode.sh` leser commit fra `code --version` på verten
  og legger `cli-alpine-<arch>` i `~/.vscode-server/code-<commit>` og `server-linux-<arch>`
  i `~/.vscode-server/cli/servers/Stable-<commit>/server` (samme oppsett som Remote - SSH
  lager selv). Da starter første tilkobling uten nedlasting på ca. 240 MB.

### 4. Fish på verten (`fish/sbx.fish`)

Lenkes til `~/.config/fish/conf.d/sbx.fish`, og `bin/` legges i `PATH`.

```fish
abbr -a sc   sbx-copilot
abbr -a ss   sbx-shell
abbr -a sv   sbx-vscode
abbr -a snb  sbx-bygg-base
abbr -a sl   'sbx ls'
abbr -a sx   'sbx exec -it'          # sx <navn> fish
abbr -a srm  'sbx rm'
```

Pluss completion for `sbx-copilot`/`sbx-shell` (kataloger, `--base`-templates) og for sandkassenavn (`sbx ls -q` e.l.).

---

## Skills

Skills håndteres **utenfor** template-en med `sbx skills`. Store-en ligger på verten og lenkes
read-only inn i agentens skills-katalog når en sandkasse starter – nye skills dukker
dermed opp i alle sandkasser ved neste oppstart, uten å bygge base på nytt.

`hooks/10-skills.sh`:

```sh
sbx skills import --force                                   # fra lokale agent-kataloger (~/.copilot/skills, …)
sbx skills add <org>/<repo> --skill <navn> --force          # fra git-repo
sbx skills update
```

Egen kommando for å vedlikeholde: `sbx skills ls`, `sbx skills update`.
Bruk `--skills=readwrite` på en sandkasse hvis den skal kunne skrive tilbake til store-en.

---

## GitHub-tilgang

Token lagres som **service secret** på verten; proxyen autentiserer forespørsler på vegne av
agenten, så tokenet aldri ligger i sandkassens filsystem.

```sh
# Alternativ A: fin-granulert PAT begrenset til egne repo (Contents + Pull requests: read/write)
sbx secret set github              # lim inn token

# Alternativ B: bruk gh på verten (arver alle gh-tilganger – bredere)
sbx secret set github --command 'gh auth token'
```

Tilgangsnivåer, fra strengest til løsest:

| Nivå | Token-rettigheter | Policy | Kommentar |
|------|-------------------|--------|-----------|
| Les | Contents: read, PR: read | `--ingen-push` | Endringer hentes ut via klonen + `sandbox-<navn>`-remote |
| PR-kommentarer | + Pull requests: write | `--ingen-push` | Agenten kan kommentere/åpne PR, men ikke pushe |
| Push | + Contents: write | – | **Standard.** Agenten oppdaterer koden selv; begrens tokenet til egne repo og bruk branch protection |

Policy med HTTP-sti (`sbx policy deny network --method … --path …`) gjør at token-rettigheter
kan snevres inn per sandkasse eller globalt, f.eks.:

```sh
# hindre git push over HTTPS selv om tokenet har skrivetilgang
sbx policy deny network github.com --method POST --path '/**/git-receive-pack'
# per sandkasse i stedet for globalt
sbx policy deny network --sandbox <navn> github.com --method POST --path '/**/git-receive-pack'
```

`hooks/20-policy.sh` legger globale `allow`-regler for verter mise trenger, og kjører
`sbx-github-policy` (se under). Push er tillatt som standard; `sbx-copilot --ingen-push`
blokkerer **per sandkasse**. En global deny-regel kan ikke
overstyres per sandkasse. Global deny kan likevel slås på med `SBX_GLOBAL_DENY_PUSH=1`.

### Hviteliste for skrivekall (`policy/github-hviteliste.txt`)

All lesing (GET, HEAD, OPTIONS) mot GitHub er tillatt. For hver `[vert]` i hvitelisten blokkeres
skrivekall (POST, PUT, PATCH, DELETE) som ikke står i fila. Standard:

| Vert | Tillatt | Hvorfor |
|------|---------|---------|
| `github.com` | `POST /*/*/git-upload-pack`, `git-receive-pack`, `info/lfs/objects/batch` | fetch, push, lfs |
| `api.github.com` | `POST /graphql` | `gh` leser via GraphQL; resolve av review-tråder finnes bare der |
| `api.github.com` | `POST /repos/*/*/pulls` | lage PR |
| `api.github.com` | `POST …/issues/*/comments`, `…/pulls/*/comments`, `…/pulls/*/comments/*/replies` | kommentere og svare på review |
| `uploads.github.com` | ingenting | |

Fila har kommenterte forslag (endre PR-tittel/-beskrivelse, be om review, labels, redigere egne
kommentarer, reaksjoner, kjøre feilede CI-jobber på nytt). Å godkjenne PR-er (`…/reviews`) er
bevisst utelatt.

**Hvorfor deny-regler?** I sbx vinner deny over allow, og en HTTP-allow kan ikke snevre inn en
host-allow. Den globale standardregelen tillater `**.github.com`, og copilot-kitet legger en
ikke-redigerbar allow for `api.github.com` på hver sandkasse. En hviteliste må derfor uttrykkes
som deny for komplementet. `bin/sbx-github-policy`:

1. bygger et tre av stiene per vert og metode (`*` = ett segment, `**` til slutt = alt under)
2. regner ut komplementet med glob-mønstre: `[!abc]*` for segmenter som ikke starter som
   en tillatt literal, eksakte prefikser (`pul`) og `literal[!/]*` for lengre segmenter
3. samler alternativene per node i én regel med `{a,b,…}` (27 regler med standardfila), og slår
   sammen metoder med like regler (f.eks. `PUT,PATCH,DELETE /**`)
4. synkroniserer mot `sbx policy ls --json`: legger til nye og fjerner utdaterte. Globale
   HTTP-deny-regler for `github.com`/`*.github.com` eies av scriptet, bortsett fra
   `/**/git-receive-pack` (`SBX_GLOBAL_DENY_PUSH`)

Verifisert med `sbx policy check http` mot en referansematcher (230 kall uten avvik), og i en
sandkasse: `git clone`, `gh api` og `gh pr list` fungerer, mens `gh api -X POST …/issues`
gir 403. Copilot selv blir ikke blokkert.

Kjente egenheter i sbx sin sti-glob (v0.54.1): `?` avvises, `[!/]` fungerer som «ett tegn»,
`x/**` treffer `x`, men `[!a]*/**` treffer ikke segmentet selv, så scriptet skriver alltid både
`g` og `g/**`.

**Begrensning:** GraphQL-mutations (f.eks. `mergePullRequest`, `deleteRef`) går til samme
`POST /graphql` som lesing og kan ikke stoppes med sti-regler. Der er tokenets rettigheter og
branch protection grensen.

---

## Mise og rask oppstart

- Alle mise-verktøy installeres i `user.sh` og **bakes inn i template-en** → ny sandkasse
  starter uten nedlastinger.
- Prosjektspesifikke verktøy (repoets `mise.toml`) som ikke finnes i base, installeres ved
  behov med `mise install` i sandkassen. Hyppig brukte versjoner flyttes inn i
  `init/files/.config/mise/config.toml` og base bygges på nytt.
- Nettverk: byggesandkassen må nå `mise.run`, `github.com`, `objects.githubusercontent.com`
  og registre for verktøyene (npm, pypi, …). Standard-policyen dekker det meste; i tillegg
  trengs bl.a. `mise-java.jdx.dev` og `download.java.net`. Sjekk med `sbx policy log` ved feil og legg
  nødvendige `allow`-regler i `hooks/20-policy.sh`.
- Base bygges på nytt periodisk (f.eks. ukentlig) for oppdaterte pakker; dato-tags gjør det
  enkelt å rulle tilbake (`sbx-copilot` kan ta `--base sbx-base:<dato>`).

Alternativ å vurdere senere: `sbx kit` (eksperimentell) for en deklarativ, delbar variant
av det samme, og `sbx env` / `sbxenv.yaml` for deklarativ oppretting.

---

## Implementeringsplan

1. **Grunnmur**
   - [x] `config.env`, katalogstruktur, `bin/` i `PATH`
   - [x] Finn standardbruker, `$HOME` og OS i copilot-imaget (`agent`, `/home/agent`, Debian 13 DHI)
2. **Init-script**
   - [x] `init/root.sh` – apt-pakker, fish, `chsh`
   - [x] `init/files/` – fish-konfig og abbr, mise-konfig, git-konfig
   - [x] `init/user.sh` – dotfiles, mise, `mise install`
   - [x] Test manuelt i en vanlig sandkasse
3. **`sbx-bygg-base`**
   - [x] Opprett → cp → hooks → exec → hooks → stop → template save → rm
   - [x] Dato-tag + `latest`, opprydding av gamle tags
   - [x] `--behold` og trap ved feil
4. **Hooks**
   - [x] `10-skills.sh` – import/add/update
   - [x] `20-policy.sh` – allow for mise/registre (deny for push per sandkasse med `--ingen-push`)
   - [x] `90-ekstra.sh` – mal for egne `sbx exec`-kommandoer
5. **`sbx-copilot` / `sbx-shell`**
   - [x] Navngiving, gjenoppta eksisterende, klone som standard/`--mount`, `--ingen-push`, `--base`
   - [x] Mål oppstartstid: `sbx create` fra base tar ~3 s, like raskt som standard-imaget –
     men alle verktøy er ferdig installert (et fullt `sbx-bygg-base` tar ~2,5 min)
6. **GitHub-token**
   - [ ] Lag fin-granulert PAT (Contents + Pull requests: read/write), `sbx secret set github`
   - [ ] Verifiser `gh pr view` og `git push` fungerer (blokkering med `--ingen-push` gir 403 – verifisert)
   - [x] Hviteliste for skrivekall (`policy/github-hviteliste.txt` + `sbx-github-policy`)
   - [x] Copilot alltid i yolo-modus (`sbx-copilot` og `copilot` i `sbx-shell`)
   - [x] Privat klone som standard, `--mount` for direkte montering ([SIKKERHET.md](SIKKERHET.md))
7. **Vert-integrasjon**
   - [x] `fish/sbx.fish` med abbr og completion
   - [x] Installasjonsscript/instruks (`install.sh`)

## Åpne spørsmål

- ~~Må sandkassen være stoppet før `sbx template save`?~~ **Ja** – `sbx-bygg-base` kjører `sbx stop` først.
- Kan én template brukes på tvers av agenter (copilot/claude), eller må det være én base per agent? (`template ls` viser `FLAVOR`.)
- ~~Overlever `chsh` til fish?~~ **Ja**, login-shell er fish i nye sandkasser. `sbx exec` kjører
  kommandoen som oppgis (bruk `sbx exec -it <navn> fish`), og agentens bash-kommandoer får
  mise-verktøy via `/etc/sandbox-persistent.sh`.
- Påvirker `sbx skills` sin read-only-lenking skills som legges direkte i `~/.copilot/skills` i template-en?
- Holder klone (standard) + lokal push fra verten, slik at agenten aldri trenger skrivetilgang til GitHub?
