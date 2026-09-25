#!/bin/bash
# Configurazione iniziale della skill: chiede i dati specifici dell'utente e li
# salva FUORI dalla cartella della skill, cosi' la skill resta pubblicabile.
#
# Uso:
#   bash configura.sh              # interattivo, chiede cio' che manca
#   bash configura.sh --mostra     # mostra la configurazione attuale e esce
#
# Exit code: 0 = configurazione scritta e verificata | 1 = interrotta o non valida
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

richiede gcloud curl jq || exit 1

# --- --mostra ------------------------------------------------------------
if [ "${1:-}" = "--mostra" ]; then
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Nessuna configurazione in $CONFIG_FILE"
    echo "Creala con:  bash \"$0\""
    exit 1
  fi
  echo "Configurazione: $CONFIG_FILE"
  echo "  Progetto Google Cloud : ${GCP_PROJECT_ID:-(assente)}"
  echo "  File client OAuth     : ${OAUTH_CLIENT_FILE:-(assente)}"
  [ -n "${GOOGLE_ADS_DEVELOPER_TOKEN:-}" ] && echo "  Developer token Ads   : presente (non mostrato)"
  if [ -n "${GCP_PROJECT_ID:-}" ]; then
    echo
    echo "Console per questo progetto:"
    echo "  Ambiti:  https://console.cloud.google.com/auth/scopes?project=$GCP_PROJECT_ID"
    echo "  Stato:   https://console.cloud.google.com/auth/audience?project=$GCP_PROJECT_ID"
  fi
  exit 0
fi

echo "=== Configurazione di collega-api-google ==="
echo
echo "Due dati, una volta sola. Restano in:"
echo "  $CONFIG_FILE"
echo "che sta fuori dalla cartella della skill: non finisce mai in un repo."
echo

# --- 1. Progetto Google Cloud -------------------------------------------
# Si propone il progetto attivo in gcloud, che nella quasi totalita' dei casi
# e' quello giusto: cosi' il dato non va cercato nella console.
PROPOSTO=$(gcloud config get-value project 2>/dev/null | grep -v '^$' | grep -v 'unset' || true)
ATTUALE="${GCP_PROJECT_ID:-}"

echo "--- 1/2. Progetto Google Cloud ---"
echo "E' il progetto che possiede il client OAuth (non serve che sia a pagamento)."
[ -n "$ATTUALE" ]  && echo "  configurato ora : $ATTUALE"
[ -n "$PROPOSTO" ] && echo "  attivo in gcloud: $PROPOSTO"
DEFAULT="${ATTUALE:-$PROPOSTO}"
if [ -n "$DEFAULT" ]; then
  printf 'Project ID [%s]: ' "$DEFAULT"
else
  printf 'Project ID: '
fi
read -r RISP
PROJECT="${RISP:-$DEFAULT}"
if [ -z "$PROJECT" ]; then
  err "Nessun project ID indicato. Interrotto."
  exit 1
fi

# Controllo di FORMA: le regole di Google sul project ID sono precise, e un
# refuso si prende qui. Serve perche' la verifica in rete (sotto) non distingue
# un ID inesistente da uno a cui non hai accesso: Google risponde 403 in
# entrambi i casi, per non far enumerare i progetti a chi tenta a caso.
if ! printf '%s' "$PROJECT" | grep -qE '^[a-z][a-z0-9-]{4,28}[a-z0-9]$'; then
  err "  ERRORE: '$PROJECT' non ha la forma di un project ID Google Cloud."
  err "          Attesi 6-30 caratteri: minuscole, cifre e trattini, inizio con una lettera."
  err "          Attenzione: NON e' il nome visualizzato del progetto, ne' il project number."
  exit 1
fi

# Verifica in rete, per quel che puo' dire.
if TOK=$(adc_token 2>/dev/null); then
  CODE=$(curl -s -o /dev/null --max-time 20 -w "%{http_code}" \
           -H "Authorization: Bearer $TOK" \
           "https://cloudresourcemanager.googleapis.com/v1/projects/$PROJECT")
  case "$CODE" in
    200) echo "  OK: progetto raggiungibile e leggibile." ;;
    403|404)
      echo "  Non verificabile da qui (HTTP $CODE). Non vuol dire che sia sbagliato:"
      echo "    Google risponde cosi' sia se il progetto non esiste, sia se esiste ma"
      echo "    l'API Cloud Resource Manager non e' abilitata o le credenziali attuali"
      echo "    non lo leggono. Si prosegue: la forma dell'ID e' corretta."
      echo "    Se piu' avanti un comando parla di un progetto che non trova, torna qui." ;;
    *)   echo "  ATT.: verifica non conclusa (HTTP $CODE). Si prosegue." ;;
  esac
else
  echo "  (Nessun ADC attivo: verifica in rete rinviata, e' atteso al primo setup.)"
fi
echo

# --- 2. File client OAuth -----------------------------------------------
echo "--- 2/2. File del client OAuth (tipo Desktop) ---"
echo "Scaricato dalla console: Credenziali -> Crea credenziali -> ID client OAuth."
echo "Serve il PERCORSO del file, mai il contenuto. Ammesso un glob (client_secret_*.json)."
[ -n "${OAUTH_CLIENT_FILE:-}" ] && echo "  configurato ora: $OAUTH_CLIENT_FILE"

# Suggerimento: si cerca nelle cartelle dove finisce di solito un download.
SUGG=""
for d in "$HOME/Downloads" "$HOME/Documents" "$HOME/.config/gcloud"; do
  [ -n "$SUGG" ] && break
  SUGG=$(glob_lista "$d/client_secret_*.json" | head -1)
done
DEFAULT_C="${OAUTH_CLIENT_FILE:-$SUGG}"
if [ -n "$DEFAULT_C" ]; then
  printf 'Percorso [%s]: ' "$DEFAULT_C"
else
  printf 'Percorso: '
fi
read -r RISP_C
CLIENT="${RISP_C:-$DEFAULT_C}"
if [ -z "$CLIENT" ]; then
  err "Nessun percorso indicato. Interrotto."
  exit 1
fi
CLIENT=$(printf '%s' "$CLIENT" | sed "s|^~|$HOME|")

TROVATI=$(glob_lista "$CLIENT")
N=$(printf '%s' "$TROVATI" | grep -c .)
if [ "$N" = "0" ]; then
  err "  ERRORE: nessun file corrisponde a: $CLIENT"
  exit 1
elif [ "$N" != "1" ]; then
  err "  ERRORE: $N file corrispondono — restringi il percorso a uno solo:"
  printf '%s\n' "$TROVATI" >&2
  exit 1
fi
TROVATO="$TROVATI"
# Controllo di forma: che sia davvero un client OAuth, e di tipo Desktop.
TIPO=$(jq -r 'if .installed then "desktop" elif .web then "web" else "ignoto" end' "$TROVATO" 2>/dev/null)
case "$TIPO" in
  desktop) echo "  OK: client OAuth di tipo Desktop." ;;
  web)     err "  ERRORE: e' un client di tipo 'Web', che con gcloud non funziona."
           err "          Creane uno di tipo 'App desktop'."
           exit 1 ;;
  *)       err "  ERRORE: il file non sembra un client OAuth di Google."
           err "          Atteso un JSON con la chiave 'installed'."
           exit 1 ;;
esac

# Il client deve appartenere al progetto scelto al passo 1. Se sono due progetti
# diversi, tutto "funziona" a meta' e in modo incomprensibile: si abilitano le API
# e si dichiarano gli ambiti su un progetto, mentre il login usa il client di un
# altro — dove quegli ambiti non sono dichiarati. L'errore che ne esce
# ("Questa app e' bloccata") non nomina mai questa causa.
CLIENT_PROJ=$(jq -r '.installed.project_id // empty' "$TROVATO" 2>/dev/null)
if [ -n "$CLIENT_PROJ" ] && [ "$CLIENT_PROJ" != "$PROJECT" ]; then
  err "  ERRORE: il client OAuth appartiene al progetto '$CLIENT_PROJ',"
  err "          ma al passo 1 hai indicato '$PROJECT'."
  err "          Scegli uno dei due e ripeti: o indichi quel progetto, o scarichi"
  err "          un client creato dentro '$PROJECT'."
  exit 1
fi
[ -z "$CLIENT_PROJ" ] && echo "  (Il file non dichiara un project_id: confronto col progetto non possibile.)"
echo

# --- 3. Scrittura --------------------------------------------------------
# Il file contiene percorsi e identificativi, non segreti: 600 comunque,
# perche' indica dove sta il client secret e non c'e' ragione di esporlo.
mkdir -p "$CONFIG_DIR" || { err "ERRORE: impossibile creare $CONFIG_DIR"; exit 1; }
chmod 700 "$CONFIG_DIR"

# Un valore opzionale gia' configurato non si perde riscrivendo il file: chi
# rilancia configura.sh per cambiare il progetto non si aspetta di restare senza
# developer token, e il check di non-regressione salterebbe Google Ads.
if [ -n "${GOOGLE_ADS_DEVELOPER_TOKEN:-}" ]; then
  RIGA_DEV_TOKEN="# Developer token Google Ads, conservato dalla configurazione precedente.
GOOGLE_ADS_DEVELOPER_TOKEN=$(shell_quote "$GOOGLE_ADS_DEVELOPER_TOKEN")"
  CONSERVATO="si"
else
  RIGA_DEV_TOKEN="# Opzionale: developer token Google Ads, se non e' gia' in ~/.claude.json.
# GOOGLE_ADS_DEVELOPER_TOKEN=''"
  CONSERVATO="no"
fi

umask 077
cat > "$CONFIG_FILE" <<CFG
# Configurazione locale di collega-api-google — NON versionare.
# Scritto da configura.sh il $(date +%Y-%m-%d\ %H:%M:%S).
# Contiene identificativi e percorsi, mai il contenuto del client secret.

GCP_PROJECT_ID=$(shell_quote "$PROJECT")
OAUTH_CLIENT_FILE=$(shell_quote "$CLIENT")

$RIGA_DEV_TOKEN
CFG
chmod 600 "$CONFIG_FILE"

if [ ! -s "$CONFIG_FILE" ]; then
  err "ERRORE: scrittura di $CONFIG_FILE non riuscita."
  exit 1
fi

# Rilettura: la configurazione e' buona se la leggono le funzioni, non se il file esiste.
( unset GCP_PROJECT_ID OAUTH_CLIENT_FILE
  . "$CONFIG_FILE"
  [ -n "${GCP_PROJECT_ID:-}" ] && [ -n "${OAUTH_CLIENT_FILE:-}" ] ) || {
  err "ERRORE: il file e' stato scritto ma non si rilegge correttamente: $CONFIG_FILE"
  exit 1; }

echo "Configurazione scritta e verificata: $CONFIG_FILE"
echo "  Progetto    : $PROJECT"
echo "  Client OAuth: $TROVATO"
[ "$CONSERVATO" = "si" ] && echo "  Developer token Google Ads: conservato (non mostrato)"
echo
echo "Da fare una volta sola nella console, prima del primo login:"
echo "  1. Dichiara gli ambiti che ti servono:"
echo "     https://console.cloud.google.com/auth/scopes?project=$PROJECT"
echo "  2. Porta l'app 'In produzione' (altrimenti i token scadono in 7 giorni):"
echo "     https://console.cloud.google.com/auth/audience?project=$PROJECT"
echo
echo "Poi:  bash \"$(dirname "$0")/backup-adc.sh\"  e  bash \"$(dirname "$0")/comando-login.sh\""
