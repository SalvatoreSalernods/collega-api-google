# collega-api-google

Skill per [Claude Code](https://code.claude.com/docs/en/overview) che collega una **nuova API
Google** alle credenziali Application Default (ADC) della macchina — Search Console, Tag
Manager, Business Profile, YouTube Data, Merchant Center, Drive, Calendar — **senza rompere
gli MCP Google che già funzionano**.

## Il problema che risolve

L'API Google, in sé, è documentata e lineare. Quello che ferma tutti è ottenere il permesso di
chiamarla, e ogni ostacolo di quella catena restituisce un errore che indica la causa sbagliata:

| Quello che vedi | Quello che è davvero |
|---|---|
| `403 SERVICE_DISABLED` | l'API non è abilitata sul progetto |
| `403 ACCESS_TOKEN_SCOPE_INSUFFICIENT` | credenziali valide, scope mancante |
| «Questa app è bloccata» | manca `--client-id-file`: gcloud sta usando il proprio client generico |
| le credenziali scadono ogni ~7 giorni | l'app OAuth è in stato "Testing", non "In produzione" |
| un MCP che funzionava smette di funzionare | un login precedente ha **sovrascritto** gli scope |

L'ultima riga è la ragione vera di questa skill.

## Il principio

**Gli scope OAuth non si sommano: si sostituiscono.**

`gcloud auth application-default login --scopes=...` non aggiunge il permesso nuovo: riscrive
il file ADC con **solo** ciò che hai elencato. Se stai già usando Google Ads e Analytics e
autorizzi Tag Manager elencando i soli scope di Tag Manager, gli altri due smettono di
funzionare all'istante — senza alcun avviso. L'errore che vedrai settimane dopo, su tutt'altro
prodotto, non punta a questa causa.

Da qui le due regole che la skill impone: **backup prima**, **lista completa sempre**. E il
comando di login non si scrive a mano: lo genera uno script leggendo gli scope realmente
attivi sul token.

## Cosa contiene

```
skills/collega-api-google/
├── SKILL.md                        la procedura in 7 passi + diagnostica
└── scripts/
    ├── configura.sh                chiede e verifica i tuoi dati, una volta sola
    ├── backup-adc.sh               backup verificato + rotazione (exit code parlante)
    ├── comando-login.sh            costruisce il comando di login dagli scope ATTIVI
    ├── check-non-regressione.sh    interroga gli MCP esistenti: hai rotto qualcosa?
    └── lib.sh                      funzioni condivise
```

Ogni script **fallisce rumorosamente** invece di produrre un risultato parziale: una lista di
scope incompleta o un backup che si dichiara riuscito senza esserlo sono più pericolosi di un
errore, perché ti fanno procedere convinto di avere una rete che non c'è.

## Requisiti

- [gcloud CLI](https://docs.cloud.google.com/sdk/docs/install) — macOS, Windows o Linux
- `jq`, `curl`, `bash` (compatibile con la 3.2 di macOS: niente `mapfile` né array associativi)
- un progetto Google Cloud (gratuito) con un **OAuth Client ID di tipo App desktop**
- accesso, dentro il prodotto Google, alle risorse su cui vuoi lavorare: l'autorizzazione
  tecnica non sostituisce l'invito a un account

## Installazione

Come plugin, dal marketplace del repo:

```bash
claude plugin marketplace add SalvatoreSalernods/collega-api-google
claude plugin install collega-api-google
```

Oppure a mano, con un symlink nella cartella delle skill:

```bash
git clone https://github.com/SalvatoreSalernods/collega-api-google.git
ln -s "$PWD/collega-api-google/skills/collega-api-google" ~/.claude/skills/collega-api-google
```

Poi, una volta sola:

```bash
bash ~/.claude/skills/collega-api-google/scripts/configura.sh
```

## I tuoi dati non stanno nella skill

`configura.sh` chiede il project ID e il percorso del file client OAuth, li **verifica** (che il
progetto esista, che il client sia di tipo Desktop e non Web) e li scrive in:

```
~/.config/collega-api-google/config.env      # dir 700, file 600
```

Fuori dalla cartella della skill, quindi fuori da qualsiasi repo. Nella skill non c'è nessun
identificativo, nessun percorso personale, nessun segreto — ed è per questo che si può
pubblicare senza bonifiche a mano ogni volta.

Il **contenuto** del file client (il client secret) non viene mai letto, stampato o copiato:
circola solo il percorso. Vale anche per gli output degli script, che stampano il motivo
d'errore riferito da Google e non la risposta grezza, che conterrebbe email e client ID.

## Il perimetro minimo

La skill sostiene una scelta esplicita: **omettere gli scope di scrittura pericolosi finché non
servono davvero**. Senza `tagmanager.publish`, mandare per errore qualcosa in produzione sul
sito di un cliente non è improbabile — è tecnicamente impossibile. Verificato sul campo: il
tentativo di pubblicazione riceve un `403` e la versione live non cambia.

Il taglio vale in due sensi — senza `delete.containers` non puoi nemmeno cancellare un
container di prova via API, e lo fai a mano in trenta secondi. È il prezzo giusto: un permesso
permanente sull'ADC costa più del fastidio che evita.

## Serve un MCP per questa API?

Spesso no, e la skill lo dice invece di venderti un'integrazione. Le chiamate REST dirette
bastano quando l'uso è occasionale o quando la sequenza la conosci già. Un server MCP si
giustifica quando il modello deve **scegliere da solo** fra molte operazioni, in sessioni
diverse. In quel caso l'accesso è già risolto: ci costruisci sopra.

## Licenza

MIT — vedi [LICENSE](LICENSE).
