# Sikkerhet

Copilot kjører i **yolo-modus** i sandkassene: alle verktøy og kommandoer godkjennes uten å
spørre. Det er sandkassen, GitHub-tokenet og nettverkspolicyen som setter grensene, ikke
agenten selv. Endringer skal gjennom review på PR før de når `main`. Dette dokumentet
beskriver hva som er beskyttet, hva som ikke er det, og hva du bør gjøre.

## Trusselbildet

Det realistiske problemet er ikke at agenten «vil» gjøre noe galt, men **prompt injection**:
agenten leser tekst skrevet av andre (issues, PR-kommentarer, README-er i avhengigheter,
nettsider, feilmeldinger) og kan bli lurt til å følge instruksjoner som står der. I yolo-modus
blir instruksjonene utført uten at du ser dem først.

Gå derfor ut fra at agenten **kan gjøre alt den har tilgang til**, og begrens tilgangen.

## Hva som er beskyttet

| Lag | Beskyttelse |
|-----|-------------|
| Sandkasse (microVM) | Agenten ser bare sandkassens filsystem, ikke resten av verten. |
| Privat klone (standard) | Repoet klones inn i sandkassen. Agenten kan ikke endre filer på verten (verts-repoet er bare montert skrivebeskyttet på `/run/sandbox/source`, så ucommittede filer der kan leses). |
| Secrets | GitHub-tokenet ligger på verten og legges på av proxyen. Det finnes ikke i sandkassen og kan ikke kopieres ut. |
| Nettverkspolicy | TCP til alle verter er tillatt, med mindre en eksplisitt deny-regel eller overordnet policy blokkerer det. |
| GitHub-hviteliste | Skrivekall mot GitHub er begrenset til [policy/github-hviteliste.txt](policy/github-hviteliste.txt): fetch/push, lage PR, kommentere, GraphQL. |

## Hva som *ikke* er beskyttet

### 1. Alt tokenet kan gjøre via GraphQL

`POST /graphql` er tillatt fordi `gh` bruker det til lesing (`gh pr view/list/checks`,
`gh issue list`) og fordi review-tråder bare kan resolves der. Policyen ser bare metode og
sti, ikke innholdet, så **alle GraphQL-mutations tokenet har rettigheter til er mulige**,
blant annet:

- `mergePullRequest`, `closePullRequest`, `updatePullRequest`
- `createCommitOnBranch` – committe rett på en branch uten `git push`, også med `--ingen-push`
- `createRef`, `updateRefs`, `deleteRef` – lage, flytte og slette brancher og tags
- `submitPullRequestReview` med APPROVE på andres PR-er, i ditt navn
- `createRepository` – f.eks. et offentlig repo som privat kode kan pushes til

Grensen her er **tokenets rettigheter**. Se [GitHub-token](#github-token).

### 2. CI-secrets via workflows

Kan agenten pushe en branch, kjører CI på den – med repoets secrets. Med Workflows-rettighet
kan den endre `.github/workflows/` direkte. Uten kan den fortsatt endre byggescript eller
tester som eksisterende workflows kjører. Secrets som gir tilgang til produksjon må derfor
ligge i GitHub Environments med påkrevd godkjenning.

### 3. Alle repo tokenet har tilgang til

Hvitelisten tillater push og kommentarer mot `/repos/*/*`, altså alle repo tokenet når,
inkludert offentlige repo andre eier (kommentarer kan brukes til å lekke data). Begrens
tokenet til utvalgte repo, eller bytt `*` med eieren i hvitelisten, f.eks.
`POST /repos/domstol/*/pulls`.

### 4. Åpent nettverk

Agenten kan nå dokumentasjon, pakkeregistre og andre TCP-verter, og kan sende kode og andre
data ut av sandkassen uten credentials. Review før merge hindrer ikke slik datalekkasje
eller andre handlinger agenten allerede har utført. Gi derfor sandkassen bare tilgang til
data du tåler at kan sendes ut.

GitHub-reglene gjelder de konkrete vertene i hvitelisten og HTTP-trafikk proxyen kan
kontrollere. Nettverkspolicyen er ikke en fullstendig garanti mot omgåelse, blant annet
for krypterte forbindelser proxyen ikke dekrypterer. Tokenets rettigheter og branch
protection er fortsatt viktige.

### 5. `--mount`: filer som kjøres på verten

Med `--mount` skriver agenten direkte i repoet på verten. Disse kjøres senere **på verten**,
utenfor sandkassen:

- `.git/hooks/*`, og `core.hooksPath` / `core.fsmonitor` i `.git/config` (kjøres ved
  `git commit`/`git status`)
- `mise.toml` (env, hooks, tasks), `.envrc` (direnv)
- `.vscode/tasks.json`, `.vscode/settings.json`
- `package.json`-scripts, `Makefile`, `gradlew`, testkode

Bruk `--mount` bare for repo og oppgaver du stoler på, og se over endringene før du kjører
noe på verten. Med privat klone (standard) er `.git/` på verten urørt, men filer som
`mise.toml` og `.envrc` blir med når du sjekker ut agentens commits. Se over diffen først.

## Anbefalinger

### GitHub-token

Bruk et **eget fin-granulert PAT** for sandkassene, ikke `gh auth token`. Et OAuth-token fra
`gh` med scopes som `repo` og `workflow` gir tilgang til alle repo du har tilgang til,
inkludert webhooks, collaborators og workflows.

| Innstilling | Verdi |
|-------------|-------|
| Repository access | Only select repositories |
| Contents | Read and write |
| Pull requests | Read and write |
| Metadata, Actions, Checks, Commit statuses, Issues | Read-only |
| Workflows, Administration, Secrets, Environments | **Ingen tilgang** |
| Expiration | Kort, f.eks. 30–90 dager |

```sh
sbx secret set github    # lim inn tokenet
```

Uten Workflows-rettighet avviser GitHub push som endrer `.github/workflows/`. Med disse
rettighetene kan heller ikke GraphQL gjøre mer enn hvitelisten i praksis åpner for.

### I repoene

- Ruleset/branch protection på `main`: krev review fra en annen, blokker force-push og sletting.
- Legg produksjons-secrets i Environments med påkrevde reviewers.
- Krev godkjenning før workflows kjører for PR-er fra eksterne bidragsytere.

### I bruk

- La standard (privat klone) være standard. Bruk `--mount` bevisst.
- Bruk `--ingen-push` når agenten bare skal lese eller foreslå endringer.
- Se over `git diff` / `git log -p` før du sjekker ut eller kjører agentens commits på verten.
- Følg med i `sbx policy log`, og utvid hvitelisten bare når agenten trenger det.
- Ikke gi sandkassene flere secrets eller MCP-servere enn de trenger (`sbx secret ls`,
  `sbx mcp ls`).

## Sjekkliste

- [ ] Fin-granulert PAT uten Workflows/Administration, lagt inn med `sbx secret set github`
- [ ] `sbx-github-policy` kjørt (og `--vis` viser ingen endringer)
- [ ] Ruleset på `main` i repoene agenten jobber i
- [ ] Produksjons-secrets bak Environments med godkjenning
- [ ] Sandkasser opprettet uten `--mount` med mindre det er et bevisst valg
