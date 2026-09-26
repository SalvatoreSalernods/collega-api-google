---
name: collega-api-google
description: "Collega una NUOVA API Google (Search Console, Business Profile, YouTube Data, Merchant Center, Tag Manager, Calendar, Drive…) alle credenziali ADC condivise senza rompere gli MCP già funzionanti — e la usa subito via REST. Copre l'intera catena di ostacoli che si incontra ogni volta e i cui messaggi d'errore puntano quasi sempre nella direzione sbagliata: API disabilitata sul progetto, scope OAuth insufficienti, 'Questa app è bloccata', ambiti da dichiarare a mano nel consent screen, scadenza dei refresh token a 7 giorni. Include backup e rollback delle credenziali, test di non-regressione sugli MCP esistenti (Google Ads, GA4, GTM) e la regola del perimetro minimo di scope. Attiva quando l'utente dice 'colleghiamo l'API X di Google', 'voglio usare Search Console/Business Profile/YouTube da qui', 'aggiungiamo uno scope', 'ho un 403 insufficient authentication scopes', 'ACCESS_TOKEN_SCOPE_INSUFFICIENT', 'Questa app è bloccata', 'devo rifare il login gcloud', 'mi chiede di ri-autenticarmi ogni settimana', 'serve un MCP per questa API Google?', 'ho abilitato l'API ma dà 403'. Attiva anche se nomina solo l'API Google che vuole usare e non la skill. NON attivare per: usare API Google GIÀ collegate e funzionanti (Google Ads, GA4, e in generale un MCP che già risponde), né per scrivere un server MCP da zero una volta che l'accesso funziona (usa mcp-server-dev:build-mcp-server), né per problemi di permessi DENTRO un prodotto Google (utente non invitato a un account GTM o Ads: è un invito da fare, non uno scope)."
---

# Collega una nuova API Google

Il percorso completo da "questa API Google mi servirebbe" a "la sto chiamando", **senza
rompere quello che già funziona**.

> **Il rischio non è l'API nuova. È l'ADC.** Le credenziali Application Default sono condivise
> fra tutti gli MCP Google configurati sulla macchina: un login fatto male li rompe tutti
> insieme, in silenzio, e te ne accorgi giorni dopo. Il grosso di questa skill serve a
> evitare quello.

## Il perimetro: cosa fa questa skill, e cosa presuppone

Fa una cosa: **aggiungere un'API a credenziali ADC condivise, con backup e verifica dei
permessi.** Presuppone cioè che più strumenti sulla stessa macchina usino lo stesso file ADC —
il caso normale di chi installa gli MCP ufficiali di Google (`google-ads-mcp`, `analytics-mcp`),
che per default si autenticano così.

Non è l'unica architettura possibile. Ma prima di proporre alternative, ricorda che **l'utente
non ha scelto di condividere l'ADC**: è ciò che si ottiene non facendo niente di speciale, perché
`gcloud` scrive un file solo e gli MCP ufficiali leggono quel file. Non trattarlo come un errore
suo.

### Gate: cosa tenere insieme e cosa isolare

**Le chiavi che aprono solo per guardare possono stare nello stesso mazzo. Quelle che aprono per
cambiare stanno da sole.** Il motivo è che nell'ADC condiviso ogni strumento eredita i permessi di
tutti gli altri: uno scope di scrittura ce l'hanno tutti, non solo chi ne ha bisogno.

**Quando l'utente chiede di aggiungere uno scope di SCRITTURA a un ADC condiviso, fermati e
proponi l'isolamento prima di procedere.** Non rifiutare: spiega il travaso di poteri, di' quanto
costa separare, e se l'utente conferma procedi con la sua scelta.

| | Esempi | Regola |
|---|---|---|
| Insieme | Search Console, Analytics, Google Ads, YouTube **in sola lettura** | nessun danno possibile, non c'è niente da isolare |
| Isolare | **Merchant Center**: l'unico scope è `content`, che include la scrittura su prodotti e prezzi — non esiste una variante readonly | nell'ADC comune quel potere lo erediterebbero tutti |
| Valutare | **Tag Manager** con `edit.containers`: consente di cancellare tag, trigger e variabili | senza `publish` niente arriva al sito, ma non è sola lettura |

Vincoli da conoscere prima di consigliare, verificati alla fonte:

- **YouTube non supporta i service account** (errore `NoLinkedYouTubeAccount`): serve
  l'autorizzazione dell'utente, quindi per YouTube l'ADC è l'unica strada.
- **Merchant Center**: la Content API for Shopping è **spenta dal 18 agosto 2026**, si usa la
  Merchant API; i service account sono supportati e Google li consiglia per l'uso su dati propri.
- Un service account va **invitato dentro il prodotto** (come utente o admin), altrimenti
  autentica e non vede nulla.

Come si isola, in pratica: `CLOUDSDK_CONFIG` verso un'altra directory (gli script la rispettano:
backup e controlli seguono quella, non la predefinita), oppure un service account con la sua
chiave. Nella configurazione di un MCP il percorso delle credenziali si dichiara per singolo
server, quindi isolare un solo strumento non tocca gli altri.

Il costo va detto insieme al beneficio: **un login dal browser per ogni insieme separato**, oggi
e a ogni scadenza, più il fatto di dover ricordare quale strumento pesca da quale directory. Per
questo la separazione totale conviene a chi ha molte integrazioni o processi non presidiati; per
tutti gli altri la via di mezzo — separare ciò che scrive, lasciare insieme ciò che legge — è
migliore.

## Il principio che regge tutto

**Con questo comando gli scope non si sommano: si sostituiscono.**

`gcloud auth application-default login --scopes=...` con una lista parziale non *aggiunge* il
permesso nuovo — riscrive il file ADC con **solo** quello che hai elencato. Google Ads e
Analytics smettono di funzionare all'istante, e l'errore che vedrai settimane dopo
(`403 insufficient scopes` su tutt'altro prodotto) non punta a questa causa.

Attenzione a non generalizzare: **non è una legge di OAuth.** Nei flussi web esiste
l'autorizzazione incrementale, che somma i permessi già concessi; per le app installate Google
la esclude, ed è il flusso che `gcloud` usa qui. Quindi la regola vale per lo strumento che
abbiamo in mano, non per «l'autenticazione Google» in generale — e va raccontata così.

Da qui discendono le due regole operative: **backup prima**, **lista completa sempre**.

## Passo 0 — la configurazione, una volta sola

La skill non contiene nessun dato specifico: progetto Google Cloud e percorso del file client
OAuth stanno in un file di configurazione **fuori** dalla cartella della skill. È anche il
motivo per cui non devi mai cablare quei valori in un comando: si leggono dal config.

### Prima di tutto: dove stanno gli script

Il percorso cambia con il tipo di installazione — come plugin la cartella sta sotto
`~/.claude/plugins/cache/<marketplace>/<plugin>/<versione>/`, via symlink sotto
`~/.claude/skills/` — quindi **non scrivere un percorso a memoria**: risolvilo una volta e
riusalo. Da qui in avanti i comandi usano `$SCRIPTS`.

```bash
SCRIPTS="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/collega-api-google}"
SCRIPTS="${SCRIPTS:-$HOME/.claude/skills/collega-api-google}/scripts"
ls "$SCRIPTS"   # deve elencare configura.sh, backup-adc.sh, comando-login.sh, check-non-regressione.sh
```

### La configurazione

```bash
bash "$SCRIPTS/configura.sh"
```

Chiede due cose e le verifica invece di fidarsi:

- **il project ID, nella forma giusta.** Boccia i due errori classici — il *project number*
  (le cifre) e il *nome visualizzato* (con maiuscole e spazi) — che non sono il project ID.
  Sull'esistenza del progetto, invece, dichiara il proprio limite: Google risponde `403` sia
  per un progetto inesistente sia per uno esistente ma non leggibile, per non farsi enumerare
  i progetti. Quindi lo script avvisa e prosegue, invece di fingere una verifica che non ha.
- **il file client**, che deve essere un OAuth di **tipo Desktop**: un client di tipo *Web* con
  `gcloud` non funziona, ed è un errore che altrimenti si scopre solo a login fallito.
- **che il client appartenga al progetto scelto.** Se sono due progetti diversi tutto funziona
  a metà: abiliti le API e dichiari gli ambiti su uno, mentre il login usa il client dell'altro,
  dove quegli ambiti non esistono. L'errore che ne esce è «Questa app è bloccata», che di questa
  causa non fa parola.

| | |
|---|---|
| Config | `~/.config/collega-api-google/config.env` (dir 700, file 600) |
| Chiavi | `GCP_PROJECT_ID`, `OAUTH_CLIENT_FILE` (percorso o glob), `GOOGLE_ADS_DEVELOPER_TOKEN` (opz.) |
| Rilettura | `bash "$SCRIPTS/configura.sh" --mostra` |

Se un altro script si lamenta che «non è configurato», la risposta è sempre questa: eseguire
`configura.sh`. Non inventare i valori e non chiederli a voce per poi scriverli in un comando:
è dal config che li leggono tutti gli script.

## Che cosa NON sta nel config

Il **contenuto** del file client OAuth (il client secret) non va letto, non va copiato in un
report, non va stampato in un log. Negli script e nei documenti circola il *percorso*, mai il
segreto. Il config stesso contiene solo identificativi e percorsi — ma sta a 600 perché indica
dove trovare il segreto, e non c'è ragione di renderlo leggibile ad altri.

## La procedura

### 1. Verifica cosa manca davvero

Prima di toccare qualsiasi cosa, chiama l'API e leggi l'errore. Distingue subito due mondi:

```bash
TOK=$(gcloud auth application-default print-access-token)
curl -s -w "\n[HTTP:%{http_code}]\n" -H "Authorization: Bearer $TOK" "<endpoint di lettura>"
```

- `SERVICE_DISABLED` → manca l'abilitazione dell'API (passo 2)
- `ACCESS_TOKEN_SCOPE_INSUFFICIENT` → mancano gli scope (passi 3-5)
- `PERMISSION_DENIED` **senza** menzione di scope → non è OAuth: l'account non ha accesso
  a quella risorsa dentro il prodotto Google. Si risolve con un invito, non con un login.

### 2. Abilita l'API sul progetto

Si fa da qui, senza console. Servono due cose distinte, che si confondono facilmente: lo scope
`cloud-platform` **sul token** e il permesso IAM `serviceusage.services.enable` **sul progetto**
(se il progetto è tuo, come Owner ce l'hai; su un progetto di un cliente può mancare, e l'errore
parla di permessi senza nominare IAM):

```bash
TOK=$(gcloud auth application-default print-access-token)
P=$(. ~/.config/collega-api-google/config.env && printf '%s' "$GCP_PROJECT_ID")
API=<nome>.googleapis.com

curl -s -X POST -H "Authorization: Bearer $TOK" -H "Content-Length: 0" \
  "https://serviceusage.googleapis.com/v1/projects/$P/services/$API:enable"

# verifica: deve dire ENABLED
curl -s -H "Authorization: Bearer $TOK" \
  "https://serviceusage.googleapis.com/v1/projects/$P/services/$API" \
  | python3 -c "import json,sys;print(json.load(sys.stdin).get('state'))"
```

Se all'API nuova bastava questo, fermati: **hai finito.** Non tutte le API richiedono scope
dedicati — molte rientrano in `cloud-platform`.

**Verifica però se quell'API ha requisiti propri oltre a scope e abilitazione.** Alcune non si
sbloccano con questa procedura: Business Profile richiede una **richiesta di accesso approvata da
Google** prima di rispondere, e altre hanno quote da chiedere. Se dopo abilitazione e scope
corretti l'API rifiuta ancora, cerca la sua pagina «prerequisites» o «request access» invece di
rifare il login: non è un problema di credenziali e nessun passo di questa skill lo risolve.

### 3. Backup dell'ADC

Non negoziabile, ed è l'unica rete che hai:

```bash
bash "$SCRIPTS/backup-adc.sh"
```

Salva credenziali + scope correnti in `~/.config/gcloud/backups/` con timestamp, verifica che
la copia corrisponda davvero all'originale, e ruota i backup tenendo gli ultimi 10.

**Leggi il codice di uscita prima di proseguire:**

| | |
|---|---|
| `0` | backup verificato, puoi ri-autenticarti — **oppure** non c'era nessun ADC da salvare: è il primo collegamento, non c'è niente da perdere |
| `1` | backup **non** riuscito — fermati, non ri-autenticarti |
| `2` | credenziali salvate ma scope non registrati (illeggibili, o scrittura del file fallita): il rollback funziona, la ricostruzione del comando no |

Al **primo collegamento** su una macchina non esiste ancora nessun ADC: lo script lo dice e ti
manda avanti, invece di trattarlo come un guasto. Da quel momento in poi il backup serve, e
`comando-login.sh` va eseguito con la lista completa.

**Rollback:** copia il file `.json` salvato sopra `~/.config/gcloud/application_default_credentials.json`.
Funziona perché un nuovo login non revoca il refresh token precedente — che è anche il motivo
per cui i backup vecchi restano credenziali vive: cancellarli non li revoca, per farlo davvero
serve [myaccount.google.com/permissions](https://myaccount.google.com/permissions).

### 4. Dichiara gli scope nel consent screen — a mano, in console

Questo passaggio **non ha API**: va fatto nel browser, ed è il punto in cui ci si blocca
sempre. Guida l'utente click per click, senza gergo (la URL con il progetto giusto la stampa
`configura.sh --mostra`):

1. Google Auth Platform → **Data Access** — `https://console.cloud.google.com/auth/scopes?project=<PROJECT_ID>`
2. *Aggiungi o rimuovi ambiti* → scorri **in fondo** al pannello → *Aggiungi ambiti manualmente*
3. Incolla i nuovi scope, uno per riga → *Aggiungi alla tabella* → *Aggiorna* → *Salva*

Compariranno sotto "I tuoi ambiti sensibili" con un triangolo giallo e la dicitura
**"Approvazione obbligatoria"**. È atteso e **non blocca nulla**: la verifica Google riguarda
la distribuzione dell'app a terzi, non l'uso sul proprio account. Dillo prima che l'utente lo
veda — è il punto in cui più facilmente si interrompe la procedura a metà, convinti di aver
sbagliato qualcosa.

### 5. Controlla lo stato di pubblicazione — prima del login

Google Auth Platform → **Audience** — `https://console.cloud.google.com/auth/audience?project=<PROJECT_ID>`

Deve dire **"In produzione"**. Se dice "Test", va pubblicata **adesso**, non dopo:
un'autorizzazione emessa in stato Test nasce con scadenza a 7 giorni e se la porta dietro
anche se pubblichi l'app subito dopo. Faresti il login due volte.

Questo stato non è leggibile da nessuna API: si verifica solo guardando la console.
Chiedi all'utente cosa vede, non darlo per fatto.

### 6. Ri-autentica con la lista COMPLETA

Non scrivere il comando a mano. Fattelo generare dagli scope realmente attivi:

```bash
bash "$SCRIPTS/comando-login.sh" tagmanager.publish
```

Accetta la forma breve (`tagmanager.publish`) o l'URL completo, segnala quelli già presenti,
e stampa il comando pronto. Se non riesce a leggere gli scope **si ferma invece di proporne
uno parziale**: un comando incompleto qui cancella accessi funzionanti.

`--client-id-file` non è opzionale. Senza, gcloud usa il proprio client generico, che Google
non autorizza per gli scope dei prodotti marketing: il login fallisce con **"Questa app è
bloccata"**, un messaggio che non nomina mai la causa vera.

Cosa vedrà l'utente, e va detto in anticipo perché sembra un errore:
"Google non ha verificato questa app" → **Avanzate** → **Apri \<nome-progetto\> (non sicuro)**.

### 7. Verifica, e soprattutto verifica di non aver rotto niente

```bash
bash "$SCRIPTS/check-non-regressione.sh"
```

La domanda a cui risponde non è «quali API rispondono adesso» ma **«ho perso qualcosa rispetto
a prima del login»**. La differenza decide tutto: guardando solo il presente, uno scope svanito
sembra un servizio che non usi, e il guasto peggiore passerebbe per normalità.

Il «prima» è la lista che `backup-adc.sh` ha salvato accanto alle credenziali copiate
(`adc-*.scopes.txt`). Lo script confronta quella con gli scope di adesso:

- **scope sparito** → `exit 1`, con l'istruzione di tornare indietro. È la sovrascrittura.
- **rimozione voluta** (hai tolto `publish` per la regola del permesso minimo) → dichiarala e
  passa: `RIMOSSI_ATTESI=tagmanager.publish bash "$SCRIPTS/check-non-regressione.sh"`. Quell'API
  non viene più interrogata, perché il suo 403 è il risultato che volevi.
- **nessun backup di riferimento** → `exit 2` e lo dice: senza il «prima» non può escludere una
  perdita, e non deve far credere il contrario.

Le sonde girano sulle API autorizzate **prima o adesso** (unione, non intersezione), così quella
che funzionava e non funziona più viene interrogata proprio per mostrare il danno. Sul `403`
distingue il guasto di credenziali da ciò che credenziali non è — API disabilitata, account non
invitato, developer token non valido — perché in quei casi il rollback annullerebbe un ADC sano.

| Uscita | Significato |
|---|---|
| `0` | nessuno scope perso e tutte le API attese rispondono |
| `1` | **regressione** (scope sparito) o guasto di credenziali → rollback subito |
| `2` | non conclusivo (nessun riferimento) o anomalia che non riguarda le credenziali |

Il `403` non vale da solo come prova di un guasto di credenziali: lo script legge il messaggio
di Google e lo classifica come tale **solo** se parla di scope insufficienti. Un `403` da API
disabilitata, da account non invitato alla risorsa o da developer token non valido finisce in
`2`, con la causa scritta — perché in quei casi il rollback annullerebbe un ADC sano per un
problema che sta altrove.

Poi rifai la chiamata del passo 1: deve rispondere 200.

## Il perimetro minimo di scope

**Ometti gli scope di scrittura pericolosi finché non servono davvero.** Un permesso che il
token non ha è un errore che non puoi commettere — vale più di qualsiasi cautela procedurale,
perché non dipende dall'attenzione di nessuno.

Caso reale: collegando Tag Manager abbiamo lasciato fuori `tagmanager.publish`. Un tentativo
di pubblicazione ha restituito 403 e il container è rimasto offline. La stessa scelta ha impedito
anche di *cancellare il container* di prova via API — eliminato a mano in trenta secondi. Il
perimetro taglia in due sensi, ed è il prezzo giusto.

**Non dire però che senza `delete` cancellare diventa impossibile: è falso.** Verificato alla
fonte: `tags.delete` richiede `tagmanager.edit.containers`, quindi chi ha il permesso di
modificare può **eliminare tag, trigger e variabili** dentro un workspace.
`tagmanager.delete.containers` riguarda la cancellazione **del container**, non del suo
contenuto.

Quel che il perimetro garantisce davvero, e che vale comunque la pena: senza `publish`, **niente
di tutto questo arriva al sito del cliente.** Le modifiche e le cancellazioni restano nel
workspace, e la versione pubblicata non cambia. È una protezione sul risultato visibile, non
sull'integrità dei dati di configurazione — dillo così, senza arrotondare.

Quando l'utente chiede un'operazione che il perimetro blocca, la scelta di default è
**farla a mano nell'interfaccia**, non allargare gli scope. Proponi l'allargamento solo se
l'operazione è ricorrente e automatizzata.

## Diagnostica: l'errore dice una cosa, la causa è un'altra

| Errore | Causa reale | Passo |
|---|---|---|
| `SERVICE_DISABLED` | API non abilitata sul progetto | 2 |
| `ACCESS_TOKEN_SCOPE_INSUFFICIENT` | scope assente dall'ADC | 4-6 |
| "Questa app è bloccata" | manca `--client-id-file`, o scope non dichiarati in console | 4, 6 |
| `PERMISSION_DENIED` senza scope | l'account non ha accesso alla risorsa: serve un invito | — |
| Funzionava, ora chiede login ogni ~7 giorni | app OAuth tornata in stato "Test" | 5 |
| Google Ads dà 404 | versione API vecchia nell'URL: alza `ADS_VER` | — |
| Un MCP smette di funzionare dopo un login | scope sovrascritti | rollback, poi 6 |
| "non è configurato" da uno script | manca il config | 0 |

## Serve davvero un MCP?

Domanda da porsi **prima** di costruire qualcosa: spesso no.

Le chiamate REST dirette bastano quando l'uso è occasionale, o quando la sequenza di
operazioni è nota in anticipo e la scrivi tu. L'intera automazione di Tag Manager — creare
container, variabili, trigger, tag, versioni — è stata fatta con `curl`, senza alcun MCP.

Un server MCP si giustifica quando il modello deve **scegliere da solo** fra molte operazioni,
in sessioni diverse, senza che tu gli rispieghi ogni volta il contesto. In quel caso l'accesso
è già risolto da questa skill: passa a `mcp-server-dev:build-mcp-server` e costruisci il server
sopra credenziali che sai funzionanti.

## Trappole da ricordare

- **Non esporre mai il client secret** nei file di lavoro, negli artifact o nei log. Nella skill
  e nei report va il *percorso* del file, mai il contenuto.
- **Project ID e project number** sono lo stesso progetto: `serviceusage` accetta entrambi.
  Un errore che nomina la lunga sequenza di cifre non parla di un altro progetto.
- **In zsh `$VAR:metodo` rompe l'espansione**, in bash no. Verificato: con `W=abc`, `bash` dà
  `abc:create_version`, `zsh` dà `abcreate_version`, perché `:c` è un modificatore di espansione
  di zsh e si mangia due caratteri. Dato che la shell predefinita di Claude Code su macOS è zsh,
  le API Google con metodi custom `:` vogliono l'URL completo o `${VAR}` con le graffe, non
  `$VAR:metodo`.
- **Un login fallito non sovrascrive l'ADC.** Prima di farti prendere dal panico, confronta:
  `diff ~/.config/gcloud/backups/<ultimo>.json ~/.config/gcloud/application_default_credentials.json`
- **`CLOUDSDK_CONFIG`, se impostata, sposta l'ADC.** `gcloud` legge e riscrive le credenziali
  sotto quella directory, non sotto `~/.config/gcloud`: gli script la rispettano, e senza quel
  rispetto un backup riuscirebbe proteggendo un file che il login non tocca — il guasto peggiore,
  perché silenzioso.
- **Un glob dentro un percorso con spazi** si spezza in due parole se non si azzera `IFS`:
  è il motivo per cui gli script usano `glob_lista()` invece di `ls $pattern`.
- **`/bin/bash` su macOS è la 3.2**, non la 4: niente `mapfile`, `readarray` o array associativi
  negli script della skill.
- **Verifica sul campo della pubblicazione:** se dopo 8+ giorni le API rispondono senza
  ri-login, lo stato "In produzione" sta facendo il suo lavoro.
