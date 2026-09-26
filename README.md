# collega-api-google

Collegare **Search Console, Tag Manager, Business Profile, YouTube, Merchant Center** — e in
generale qualunque servizio Google — a un assistente AI o alla riga di comando, per leggere e
scrivere dati senza aprire l'interfaccia.

Non è difficile chiamare queste API. È difficile **ottenere il permesso** di chiamarle: è lì che
si perde un pomeriggio, e i messaggi d'errore che incontri indicano quasi sempre una causa
sbagliata. Questo repo raccoglie la procedura che funziona, verificata sul campo.

C'è un secondo motivo, meno ovvio e più importante: **il modo sbagliato di chiedere un permesso
nuovo ti toglie quelli che avevi già**. Se stai usando Google Ads e Analytics e colleghi Tag
Manager senza l'accortezza giusta, i primi due smettono di funzionare — in silenzio, e te ne
accorgi giorni dopo. Evitare questo è il cuore del lavoro.

> **Il perimetro, detto subito.** Questo repo fa una cosa: **aggiungere un servizio Google a un
> insieme di credenziali condivise**, con copia di sicurezza e verifica dei permessi. Dà per
> scontato che più strumenti sulla tua macchina usino le stesse credenziali — il caso normale se
> hai installato gli MCP ufficiali di Google, che si autenticano così per default. Se la tua
> situazione è diversa, guarda [più sotto](#e-se-invece-tenessi-le-credenziali-separate): a volte
> la risposta giusta è non condividerle affatto.

## Due modi di usarlo, scegli in base a cosa ti serve

| | |
|---|---|
| **Lo faccio una volta e basta** | Apri la **[guida per collegare un'API Google](guida-collega-api-google.md)**: la procedura completa in un unico file, comandi compresi. Niente da installare. Va bene anche da incollare a ChatGPT o Claude perché ti accompagni. |
| **Lavoro in Claude Code e lo rifarò** | Installa la skill (istruzioni sotto). Automatizza i passaggi delicati e ti riconosce gli errori mesi dopo, quando non ricorderai più niente. |

La seconda non è un vezzo: appena aggiungi un secondo servizio Google, la procedura si rifà da
capo. E la parte che si ripete è proprio quella dove un passo saltato fa danni.

## Il meccanismo da capire, prima dei comandi

Quando autorizzi un programma ad agire su un servizio Google, gli consegni un **mazzo di
chiavi** — nel gergo tecnico si chiamano *scope*, e sono i permessi specifici: «leggere
Analytics», «modificare i container di Tag Manager», e così via.

Il punto che frega tutti: **con il comando che si usa qui, quel mazzo non si arricchisce — si
rifà da zero.** Ogni volta che autorizzi qualcosa, il comando riscrive il mazzo con **solo** le
chiavi che hai elencato in quel momento. Le altre non vengono aggiunte a quelle vecchie:
cancellano le vecchie.

Una precisazione che conta se leggi altra documentazione e ti sembra di trovare il contrario:
**non è una regola di OAuth in generale.** Nelle applicazioni web esiste un meccanismo che somma
i permessi già concessi; per i programmi installati sul tuo computer — la situazione di questa
guida — Google non lo prevede. Quindi la regola vale per lo strumento che hai in mano, ed è
quello che conta in pratica.

Da qui le due regole che valgono in ogni caso, e che il resto di questo repo serve solo a far
rispettare:

1. **Copia il mazzo prima di rifarlo.** Serve a tornare indietro se qualcosa va storto.
2. **Elenca sempre tutte le chiavi**, non solo quella nuova. Comprese quelle che usi per altri
   servizi e di cui forse ti sei dimenticato.

Per la seconda regola la memoria non basta, ed è il motivo per cui qui c'è uno script invece di
un promemoria: il comando di autorizzazione viene **generato leggendo le chiavi che hai in questo
momento**, così non dipende da cosa ti ricordi.

## Gli errori che incontrerai, e cosa vogliono dire davvero

Questa tabella è metà del valore del repo. Nessuno di questi messaggi nomina la causa vera.

| Quello che leggi | Quello che è davvero | Dove si risolve |
|---|---|---|
| `SERVICE_DISABLED` | il servizio non è ancora attivato sul tuo progetto Google | passo 2 della guida |
| `ACCESS_TOKEN_SCOPE_INSUFFICIENT` | le credenziali sono buone, manca il permesso specifico | passi 4-6 |
| «Questa app è bloccata» | stai usando un'identità generica che Google non autorizza per questi servizi | passo 6 |
| Le credenziali scadono ogni settimana | la tua app è rimasta in stato «Test» | passo 5 |
| `PERMISSION_DENIED`, senza parlare di permessi tecnici | il tuo account non è stato invitato a quella risorsa: è un invito da chiedere, non un problema tecnico | — |
| Un collegamento che funzionava smette di funzionare | un'autorizzazione successiva ha sovrascritto il mazzo di chiavi | si torna indietro dalla copia |

## Il permesso minimo: la parte che protegge i tuoi clienti

Una scelta su cui questo repo insiste. Fra i permessi che potresti chiedere ci sono
**«pubblica»** e **«cancella»**. Sono le due sole operazioni davvero irreversibili — pubblicare
su Tag Manager significa toccare il sito vivo di un cliente.

Il consiglio è di **non chiederli affatto**, e di fare quelle due cose a mano nell'interfaccia
quando serve. Trenta secondi di lavoro manuale, in cambio del fatto che **mandare qualcosa in
produzione per sbaglio diventa impossibile**, non solo improbabile: il permesso non c'è.
Verificato sul campo — senza il permesso di pubblicare, il tentativo viene rifiutato e la
versione attiva sul sito non cambia.

**Quello che questa scelta non fa**, e va detto perché la differenza è sostanziale: non impedisce
ogni cancellazione. In Tag Manager il permesso di *modifica* include l'eliminazione di tag,
trigger e variabili — l'ho verificato nella documentazione del metodo, non dedotto. Il permesso
«cancella» riguarda l'eliminazione **del container intero**, non del suo contenuto.

Quindi la protezione è precisa: le modifiche e le cancellazioni restano nell'area di lavoro, e
**senza il permesso di pubblicare non arrivano al sito del cliente**. È una garanzia su ciò che
il visitatore vede, non sull'integrità della configurazione.

## E se invece tenessi le credenziali separate?

Domanda giusta, e per certe situazioni è la risposta migliore. Condividere un unico insieme di
credenziali fra tutti gli strumenti **è una scelta, non un obbligo**: è solo quella che ti
ritrovi per default se hai installato gli MCP ufficiali di Google.

L'alternativa è dare a ogni integrazione le sue credenziali, o tenerle in cartelle separate
(`gcloud` lo permette con la variabile `CLOUDSDK_CONFIG`, che questi script rispettano). Costa
un po' di configurazione all'inizio ed elimina alla radice il problema: se le credenziali non
sono condivise, rifare un'autorizzazione non può rompere nient'altro.

Come scegliere:

| La tua situazione | Cosa conviene |
|---|---|
| Devo collegare una cosa, una volta | La [guida](guida-collega-api-google.md), e basta |
| Ho più strumenti che già condividono le credenziali | Questo repo ti fa risparmiare tempo ed errori |
| Devo mantenere molte integrazioni per anni | Valuta credenziali separate: meno comodo, molto più solido |
| Uso un connettore che gestisce già l'accesso da sé | Usa il suo, e verifica quali permessi si prende |

Non c'è una risposta unica. Ma se ti trovi a **far crescere all'infinito un unico elenco di
permessi**, quello è il segnale che la separazione conviene.

## Cosa ti serve

- Un **progetto Google Cloud**, che è gratuito e serve solo da contenitore amministrativo.
- Lo **strumento a riga di comando di Google** ([gcloud](https://docs.cloud.google.com/sdk/docs/install)),
  disponibile per Mac, Windows e Linux.
- **Accesso ai dati su cui vuoi lavorare.** Questo non lo dà nessuna procedura tecnica: se non
  sei stato invitato al container Tag Manager di un cliente, non lo vedrai comunque.
- **Il ruolo giusto sul progetto Cloud.** Attivare un servizio richiede un permesso
  amministrativo sul progetto, che è cosa diversa dall'autorizzazione del programma: se il
  progetto l'hai creato tu ce l'hai, su quello di un cliente potrebbe mancarti.
- Per gli script: `bash`, `curl` e `jq` (su Mac e Linux ci sono già o si installano in un
  minuto).

Un avvertimento sulla portata: **non tutti i servizi Google si sbloccano con questa procedura.**
Alcuni chiedono un passaggio in più che nessuno script può fare al posto tuo — Business Profile,
per esempio, richiede una domanda di accesso approvata da Google. Se dopo aver attivato il
servizio e dato i permessi giusti l'API rifiuta ancora, cerca la sua pagina dei prerequisiti
invece di rifare l'autorizzazione.

## Installare la skill in Claude Code

```bash
claude plugin marketplace add SalvatoreSalernods/collega-api-google
claude plugin install collega-api-google
```

Poi, una volta sola, la configurazione:

```bash
bash ~/.claude/plugins/cache/collega-api-google/collega-api-google/*/skills/collega-api-google/scripts/configura.sh
```

Ti chiede due dati — quale progetto Google Cloud usi e dove hai salvato il file dell'identità
OAuth — e li controlla invece di fidarsi: che il progetto sia scritto nel formato giusto (i due
errori classici sono usare il *numero* del progetto o il suo *nome visualizzato*), che il file
sia del tipo corretto e che appartenga davvero al progetto che hai indicato.

## Cosa c'è dentro

| File | A cosa serve |
|---|---|
| [`guida-collega-api-google.md`](guida-collega-api-google.md) | Come collegare un'API Google, dall'inizio alla fine: da leggere, da seguire a mano o da incollare a un assistente AI. Nessuna installazione. |
| `skills/collega-api-google/SKILL.md` | Le istruzioni che segue Claude Code: gli stessi passi, più la diagnostica degli errori. |
| `scripts/configura.sh` | Chiede e verifica i tuoi due dati, una volta sola. |
| `scripts/backup-adc.sh` | Copia le credenziali **e verifica che la copia sia buona** prima di lasciarti procedere. |
| `scripts/comando-login.sh` | Genera il comando di autorizzazione leggendo i permessi che hai adesso. |
| `scripts/check-non-regressione.sh` | Confronta i permessi **prima e dopo** l'autorizzazione e ti ferma se qualcosa è sparito. Se la rimozione era voluta, lo dichiari e passa. |

Il criterio di scrittura di questi script è uno solo: **meglio un errore chiaro che un
risultato a metà**. Un backup che si dichiara riuscito senza esserlo è peggio di nessun backup,
perché ti fa procedere convinto di avere una rete che non c'è.

## Dove finiscono i tuoi dati

I due dati della configurazione stanno in un file di testo sul tuo computer:

```
~/.config/collega-api-google/config.env
```

È l'unico file che la skill crea. Per cambiare progetto rilanci `configura.sh`; per rimuovere
tutto, cancelli quel file. Con `configura.sh --mostra` vedi cosa contiene e ottieni i due
indirizzi della console Google già puntati al tuo progetto.

## Cosa fa questo codice delle tue credenziali

Domanda legittima prima di eseguire script di uno sconosciuto che toccano l'accesso ai tuoi
account Google.

- **La password dell'identità OAuth non viene mai letta né mostrata.** Del file salvato sul tuo
  computer circola solo il percorso. Le uniche due informazioni lette al suo interno sono il
  tipo di identità e il progetto a cui appartiene, per i controlli della configurazione.
- **Le copie delle credenziali restano sul tuo computer**, in una cartella accessibile solo a
  te. Attenzione a un punto: ogni copia contiene un accesso ancora valido, e cancellare il file
  non lo revoca. Per revocarlo davvero si passa da
  [myaccount.google.com/permissions](https://myaccount.google.com/permissions).
- **Gli errori mostrano il motivo riferito da Google, non la risposta completa** — che
  conterrebbe il tuo indirizzo email e l'identificativo della tua app, e che finirebbe in chiaro
  il giorno che incolli un errore in un forum.
- **Nessuna chiamata va altrove che a Google.** Nessuna raccolta di dati d'uso, nessun servizio
  di terzi.

## Serve un MCP per collegare un'API Google?

Domanda ricorrente per chi lavora con assistenti AI. Nella maggior parte dei casi **no**: se la
sequenza di operazioni la conosci già, delle normali chiamate dirette sono più semplici da
scrivere, più facili da controllare e non richiedono manutenzione. Un MCP si giustifica quando
vuoi che il modello **scelga da solo** fra molte operazioni possibili, in sessioni diverse,
senza rispiegargli ogni volta il contesto.

La parte che vale la pena risolvere bene è l'accesso, non l'integrazione. Una volta autorizzato,
ci costruisci sopra quello che ti serve.

## Licenza

MIT — vedi [LICENSE](LICENSE). Di Salvatore Salerno,
[digital strategist](https://github.com/SalvatoreSalernods).
