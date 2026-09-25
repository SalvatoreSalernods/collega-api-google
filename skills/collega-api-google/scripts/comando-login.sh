#!/bin/bash
# Costruisce il comando di ri-autenticazione ADC partendo dagli scope REALMENTE
# attivi sul token, aggiungendo quelli nuovi passati come argomenti.
#
# Uso:
#   bash comando-login.sh                                  # solo gli scope attuali
#   bash comando-login.sh tagmanager.publish               # forma breve
#   bash comando-login.sh https://www.googleapis.com/auth/webmasters.readonly
#
# Perche' esiste: gli scope OAuth non si sommano, si sostituiscono. Il modo piu'
# facile di rompere Google Ads e Analytics e' ricopiare a mano una lista scope
# incompleta. Qui la lista non dipende piu' dalla memoria di nessuno: si legge
# dal token attivo. Se il token non e' leggibile lo script SI FERMA, invece di
# proporre un comando parziale che cancellerebbe accessi funzionanti.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

richiede gcloud curl jq || exit 1

PREFIX="https://www.googleapis.com/auth/"

ATTUALI=$(adc_scopes) || {
  err ""
  err "Non posso costruire il comando senza sapere quali scope sono attivi ora."
  err "Costruirlo a memoria e' esattamente l'errore che questo script previene:"
  err "uno scope dimenticato cancella l'accesso agli altri MCP."
  err ""
  err "Se l'ADC e' irrecuperabile, recupera la lista dall'ultimo backup:"
  err "  cat \$(ls -1t $BACKUP_DIR/adc-*.scopes.txt 2>/dev/null | head -1)"
  exit 1
}

CLIENT=$(client_file) || exit 1

# Il progetto serve solo per costruire le URL della console: se non e'
# configurato non si blocca il comando di login, che non ne ha bisogno.
PROJ=$(project_id 2>/dev/null) || PROJ=""
if [ -n "$PROJ" ]; then Q="?project=$PROJ"; else Q=""; fi

# Normalizza i nuovi scope: accetta sia la forma breve sia l'URL completo.
NUOVI=""
for s in "$@"; do
  case "$s" in
    https://*) NUOVI="$NUOVI $s" ;;
    *)         NUOVI="$NUOVI ${PREFIX}${s}" ;;
  esac
done

# Unione senza duplicati, ordinata.
TUTTI=$(printf '%s\n' $ATTUALI $NUOVI | sed '/^$/d' | sort -u)

echo "Scope attivi ora ($(printf '%s\n' $ATTUALI | wc -l | tr -d ' ')):"
printf '  - %s\n' $ATTUALI
if [ -n "$NUOVI" ]; then
  echo
  echo "In aggiunta:"
  for s in $NUOVI; do
    if printf '%s\n' $ATTUALI | grep -qx "$s"; then
      echo "  - $s   (gia' presente, ignorato)"
    else
      echo "  + $s"
    fi
  done
fi

CSV=$(printf '%s\n' $TUTTI | paste -sd, -)
# Il comando qui sotto viene INCOLLATO in una shell: il percorso va quotato,
# altrimenti un nome di file con $ o backtick viene espanso al momento dell'incollo.
CLIENT_Q=$(shell_quote "$CLIENT")

cat <<TXT

--------------------------------------------------------------------
PRIMA di lanciarlo, due cose che non si vedono da qui:

  1. I nuovi scope vanno dichiarati nel consent screen, a mano:
     https://console.cloud.google.com/auth/scopes$Q
  2. Lo stato dell'app deve essere "In produzione", non "Test",
     altrimenti il token nasce con scadenza a 7 giorni:
     https://console.cloud.google.com/auth/audience$Q

E fai un backup:  bash "$(dirname "$0")/backup-adc.sh"
--------------------------------------------------------------------

gcloud auth application-default login \\
  --client-id-file=$CLIENT_Q \\
  --scopes=$CSV

Dopo il login, verifica di non aver rotto nulla:
  bash "$(dirname "$0")/check-non-regressione.sh"
TXT
