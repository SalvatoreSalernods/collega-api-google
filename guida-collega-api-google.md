# Collegare un'API Google: la procedura completa

Questa guida sta in un file solo e non richiede di installare niente. Serve a dare a un
programma — un assistente AI, uno script tuo, la riga di comando — il permesso di leggere e
scrivere sui servizi Google a cui hai accesso: Search Console, Tag Manager, Business Profile,
YouTube, Merchant Center, Analytics, Drive.

Puoi leggerla e seguirla a mano, oppure **incollarla a ChatGPT, Claude o Gemini** e farti
accompagnare passo per passo.

> **Se lo farai più di una volta** — cioè se colleghi un secondo servizio, prima o poi — nello
> stesso repo c'è una skill per Claude Code che automatizza i passaggi delicati: vedi il
> [README](README.md). Questa guida resta valida in ogni caso.

---

## La cosa da sapere prima di cominciare

Autorizzando un programma gli consegni un **mazzo di chiavi**: i permessi specifici su ciascun
servizio. Nel gergo tecnico si chiamano *scope*.

**Con il comando di questa guida quel mazzo non si arricchisce: si rifà da zero.** Il comando di
autorizzazione riscrive il mazzo con **solo** le chiavi che elenchi in quel momento. Le
precedenti non sopravvivono.

Se leggendo altra documentazione ti sembra di trovare il contrario: non è una regola di OAuth in
generale. Nelle applicazioni web esiste un meccanismo che somma i permessi già concessi; per i
programmi installati sul computer — la situazione qui — Google non lo prevede.

Conseguenza pratica: se oggi usi Google Ads e Analytics e domani autorizzi Tag Manager
elencando solo le chiavi di Tag Manager, **Ads e Analytics smettono di funzionare all'istante**,
senza alcun avviso. L'errore lo vedrai settimane dopo, su tutt'altro prodotto, e non punterà a
questa causa.

Da qui le due regole di tutta la procedura:

1. **Copia le credenziali prima di rifarle** (passo 3).
2. **Elenca sempre tutte le chiavi**, non solo quella nuova (passo 6).

---

## Cosa ti serve

- Un **progetto Google Cloud**. È gratuito e serve solo come contenitore amministrativo.
- Lo strumento a riga di comando di Google, [gcloud](https://docs.cloud.google.com/sdk/docs/install),
  per Mac, Windows o Linux.
- Un'**identità OAuth di tipo «App desktop»**, da creare nella console del progetto:
  *Credenziali → Crea credenziali → ID client OAuth → App desktop*. Si scarica come file `.json`:
  annotati dove lo salvi, perché serve al passo 6.
- **Accesso ai dati**, dentro il prodotto Google. Nessuna procedura tecnica sostituisce un
  invito: se non sei stato aggiunto al container Tag Manager di un cliente, non lo vedrai.

Nei comandi che seguono sostituisci `IL-TUO-PROGETTO` con l'identificativo del tuo progetto.
Attenzione: è la stringa con le lettere (`mio-progetto-123`), **non** il numero lungo e **non** il
nome visualizzato.

---

## Passo 1. Prova la chiamata e leggi l'errore

Prima di cambiare qualunque cosa, chiama il servizio e guarda cosa risponde. È l'errore che ti
dice quale passo ti serve, e fa risparmiare un'ora.

```bash
TOKEN=$(gcloud auth application-default print-access-token)
curl -s -w "\n[HTTP:%{http_code}]\n" -H "Authorization: Bearer $TOKEN" \
  "https://tagmanager.googleapis.com/tagmanager/v2/accounts"
```

L'indirizzo dell'esempio è quello di Tag Manager: sostituiscilo con quello del servizio che ti
interessa (lo trovi nella documentazione dell'API, alla voce «list» della risorsa più semplice).

Poi:

- `SERVICE_DISABLED` → **passo 2**
- `ACCESS_TOKEN_SCOPE_INSUFFICIENT` → **passi 3-6**
- `PERMISSION_DENIED` che non parla di permessi tecnici → non è un problema di autorizzazione:
  il tuo account non ha accesso a quella risorsa. Chiedi l'invito e fermati qui.
- Risposta `200` → è già tutto a posto.

## Passo 2. Attiva il servizio sul tuo progetto

Ogni API va attivata una volta per progetto. Serve anche un permesso amministrativo sul progetto,
che è cosa diversa dall'autorizzazione del programma: se il progetto l'hai creato tu ce l'hai, su
quello di un cliente potrebbe mancarti (e l'errore parlerà di permessi senza spiegare quale).
Dalla riga di comando:

```bash
gcloud services enable tagmanager.googleapis.com --project=IL-TUO-PROGETTO
```

Il nome del servizio segue sempre lo schema `<nome>.googleapis.com`:
`searchconsole.googleapis.com`, `mybusinessbusinessinformation.googleapis.com`,
`youtube.googleapis.com`, `content.googleapis.com` per Merchant Center.

Se negli errori ti compare a volte il nome del progetto e a volte un numero lungo: sono lo
stesso progetto, chiamato in due modi.

**Adesso riprova il passo 1.** Se risponde `200`, hai finito: molti servizi non richiedono
permessi dedicati. Vai avanti solo se leggi ancora un errore sui permessi.

> **Non tutti i servizi si sbloccano così.** Alcuni chiedono un passaggio in più che nessuna
> procedura tecnica sostituisce: Business Profile, per esempio, richiede una domanda di accesso
> approvata da Google, e altri hanno quote da richiedere. Se dopo l'attivazione e i permessi
> corretti l'API rifiuta ancora, cerca la sua pagina dei prerequisiti: non è un problema di
> autorizzazione.

## Passo 3. Copia le credenziali (la tua rete di sicurezza)

Questo passaggio non si salta. È l'unico modo di tornare indietro.

Se è la **prima volta** che autorizzi qualcosa su questo computer, il file delle credenziali non
esiste ancora: non c'è niente da copiare e niente da perdere. Salta al passo 4 e, al passo 6,
elenca solo i permessi che ti servono.

```bash
# il file delle credenziali (su Windows: %APPDATA%\gcloud\)
cp ~/.config/gcloud/application_default_credentials.json ~/credenziali-google-backup.json

# le chiavi che hai ADESSO: annotatele, servono al passo 6
TOKEN=$(gcloud auth application-default print-access-token)
curl -s -X POST -d "access_token=$TOKEN" https://oauth2.googleapis.com/tokeninfo
```

Il secondo comando risponde con un elenco alla voce `scope`: **copialo da parte**, è la lista
completa che dovrai reinserire. Il token va nel corpo della richiesta e non nell'indirizzo,
altrimenti finisce nei registri dei server che attraversa.

> Due cose da sapere sulla copia. Ripristinarla funziona perché una nuova autorizzazione non
> annulla quella precedente. Per lo stesso motivo la copia resta un accesso valido anche dopo
> mesi: cancellare il file non lo revoca, per farlo davvero si passa da
> [myaccount.google.com/permissions](https://myaccount.google.com/permissions).

## Passo 4. Dichiara i permessi nella console

Questo passaggio si fa solo nel browser, non esiste un comando. Ed è quello su cui ci si blocca.

1. Vai su **Google Auth Platform → Data Access** del tuo progetto:
   `https://console.cloud.google.com/auth/scopes?project=IL-TUO-PROGETTO`
2. *Aggiungi o rimuovi ambiti* → scorri **in fondo** al pannello → *Aggiungi ambiti manualmente*
3. Incolla i permessi che ti servono, uno per riga, poi *Aggiungi alla tabella* → *Aggiorna* →
   *Salva*

I permessi hanno la forma `https://www.googleapis.com/auth/<nome>` e li trovi nella pagina
«Authorization» della documentazione dell'API. Esempi:

| Servizio | Permesso per leggere | Permesso per scrivere |
|---|---|---|
| Search Console | `webmasters.readonly` | `webmasters` |
| Tag Manager | `tagmanager.readonly` | `tagmanager.edit.containers` |
| Analytics | `analytics.readonly` | `analytics.edit` |
| YouTube | `youtube.readonly` | `youtube` |

Compariranno sotto «I tuoi ambiti sensibili» con un triangolo giallo e la scritta **«Approvazione
obbligatoria»**. **Non blocca niente**: la verifica di Google riguarda le app distribuite ad
altre persone, non l'uso sul tuo account. È il punto in cui in molti si fermano credendo di aver
sbagliato.

### Chiedi solo i permessi che ti servono

Fra i permessi disponibili ci sono **«pubblica»** e **«cancella»**: le due sole operazioni
davvero irreversibili. Su Tag Manager pubblicare significa toccare il sito vivo di un cliente.

Il consiglio è di **non chiederli affatto** e di fare quelle due cose a mano nell'interfaccia
quando capita. Costa trenta secondi e in cambio **mandare qualcosa in produzione per sbaglio
diventa impossibile**, non solo improbabile: il permesso non c'è. Verificato sul campo — senza il
permesso di pubblicare, il tentativo viene rifiutato e la versione attiva sul sito non cambia.

Attenzione a cosa questo **non** garantisce. In Tag Manager il permesso di *modifica* comprende
l'eliminazione di tag, trigger e variabili: il permesso «cancella» riguarda l'eliminazione del
container intero, non del suo contenuto. Quindi la garanzia è che le modifiche e le cancellazioni
restano nell'area di lavoro e **non arrivano al sito** finché non pubblichi — non che nulla possa
essere cancellato.

## Passo 5. Porta l'app «In produzione» — prima di autorizzare

`https://console.cloud.google.com/auth/audience?project=IL-TUO-PROGETTO`

Se lo stato è **«Test»**, portalo **«In produzione»** adesso. È la spiegazione di un fastidio
molto comune: **le credenziali che smettono di funzionare dopo circa una settimana.** Un'app in
stato di test rilascia accessi che scadono in 7 giorni.

Va fatto **prima** del passo 6: un'autorizzazione emessa mentre l'app è in test si porta dietro
la scadenza breve anche se pubblichi l'app subito dopo, e ti tocca rifare il login.

Questo stato non è leggibile da nessuna API: si controlla solo guardando la pagina.

## Passo 6. Autorizza, con la lista completa

Qui si usa la lista che hai messo da parte al passo 3, **più** i permessi nuovi. Tutti insieme,
separati da virgola, senza spazi.

```bash
gcloud auth application-default login \
  --client-id-file="/percorso/del/tuo/client_secret_xxx.json" \
  --scopes=https://www.googleapis.com/auth/cloud-platform,\
https://www.googleapis.com/auth/analytics.readonly,\
https://www.googleapis.com/auth/webmasters.readonly
```

Due avvertenze che valgono l'intero passo:

- **`--client-id-file` non è opzionale.** Senza, il comando usa un'identità generica che Google
  non autorizza per questi servizi, e il login fallisce con **«Questa app è bloccata»** — un
  messaggio che non nomina mai la causa vera.
- **Se ometti una chiave che avevi, la perdi.** Ricontrolla la lista contro quella del passo 3
  prima di premere invio.

Nel browser vedrai «Google non ha verificato questa app»: è atteso, si procede da **Avanzate**.

## Passo 7. Controlla di non aver rotto niente

Il controllo che conta non è sul servizio nuovo — è su quelli di prima. E non è «i servizi
rispondono?», ma **«l'elenco delle chiavi è ancora completo?»**: un permesso scomparso, guardando
solo il presente, sembra un servizio che non usavi.

```bash
TOKEN=$(gcloud auth application-default print-access-token)

# le chiavi che hai adesso: confrontale con quelle del passo 3
curl -s -X POST -d "access_token=$TOKEN" https://oauth2.googleapis.com/tokeninfo

# poi prova un servizio che usavi PRIMA, es. Analytics
curl -s -o /dev/null -w "Analytics: %{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  "https://analyticsadmin.googleapis.com/v1beta/accountSummaries?pageSize=1"
```

Come leggere i risultati:

- `200` → funziona.
- `401` o `403` **che parla di permessi insufficienti** → hai perso una chiave. **Ripristina la
  copia** (sotto) e ricomincia dal passo 6 con la lista giusta.
- `403` che parla d'altro (servizio non attivato, account senza accesso) → **non** è un problema
  di autorizzazione: non ripristinare niente, il tuo mazzo di chiavi è sano.
- `404` → l'indirizzo non esiste, tipicamente una versione di API vecchia. Non c'entra con i
  permessi.

Infine ripeti il passo 1: adesso deve rispondere `200`.

### Come tornare indietro

```bash
cp ~/credenziali-google-backup.json ~/.config/gcloud/application_default_credentials.json
```

Funziona perché la nuova autorizzazione non ha annullato la precedente.

---

## Tabella di consultazione: l'errore e la causa vera

| Quello che leggi | Quello che è davvero | Passo |
|---|---|---|
| `SERVICE_DISABLED` | servizio non attivato sul progetto | 2 |
| `ACCESS_TOKEN_SCOPE_INSUFFICIENT` | manca il permesso specifico | 4-6 |
| «Questa app è bloccata» | manca `--client-id-file`, o i permessi non sono dichiarati in console | 4, 6 |
| `PERMISSION_DENIED` senza parlare di permessi tecnici | il tuo account non ha accesso alla risorsa: serve un invito | — |
| Devi rifare il login ogni ~7 giorni | app rimasta in stato «Test» | 5 |
| Un collegamento che funzionava non funziona più | un'autorizzazione successiva ha sovrascritto il mazzo | ripristina, poi 6 |
| `404` su un servizio Google | versione dell'API superata nell'indirizzo | — |

## In sintesi

La parte difficile non è l'API: è arrivare ad avere il permesso di chiamarla. Attivare il
servizio, dichiarare i permessi in console, portare l'app in produzione, e autorizzare
**senza cancellare** i permessi che avevi già. Fatto una volta, resta fatto.

Il consiglio che vale più di tutti: **chiedi il permesso minimo**. Lasciare fuori «pubblica» e
«cancella» costa trenta secondi di lavoro manuale sulle due sole operazioni irreversibili, ed
elimina alla radice la categoria di errori che davvero preoccupa quando lavori sui dati di un
cliente.
