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

# Due casi da non confondere.
#
# 1. ADC ASSENTE: e' il primo collegamento. Non c'e' nessuna lista da preservare,
#    quindi costruire il comando con i soli scope richiesti e' corretto e sicuro.
# 2. ADC PRESENTE ma illeggibile: qui ci si ferma. Una lista parziale
#    cancellerebbe accessi che esistono, ed e' il danno che questo script esiste
#    per prevenire.
if [ ! -f "$ADC_FILE" ]; then
  if [ $# -eq 0 ]; then
    err "Primo collegamento: non ci sono credenziali da estendere ($ADC_FILE assente)."
    err "Dimmi quali permessi ti servono, altrimenti non c'e' niente da chiedere:"
    err "  bash \"$0\" webmasters.readonly"
    err ""
    err "Al primo collegamento conviene includere anche cloud-platform, che serve"
    err "per attivare le API dalla riga di comando (insieme al ruolo IAM adeguato"
    err "sul progetto: se il progetto e' tuo, ce l'hai)."
    exit 1
  fi
  echo "Primo collegamento: nessuna credenziale preesistente da preservare."
  echo "Il comando conterra' i soli permessi che hai chiesto."
  echo
  ATTUALI=""
else
  ATTUALI=$(adc_scopes) || {
    err ""
    err "Le credenziali esistono ma non riesco a leggere quali permessi hanno."
    err "Qui mi fermo: costruire la lista a memoria e' esattamente l'errore che"
    err "questo script previene — uno scope dimenticato cancella accessi vivi."
    err ""
    err "Recupera la lista dall'ultimo backup e passala a mano:"
    err "  cat \$(ls -1 $BACKUP_DIR/adc-*.scopes.txt 2>/dev/null | sort -r | head -1)"
    exit 1
  }
fi

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

if [ -n "$ATTUALI" ]; then
  echo "Scope attivi ora ($(printf '%s\n' $ATTUALI | grep -c .)):"
  printf '  - %s\n' $ATTUALI
else
  echo "Nessuno scope attivo: si parte da zero."
fi
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
