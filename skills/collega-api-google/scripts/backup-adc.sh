#!/bin/bash
# Backup delle credenziali ADC prima di una ri-autenticazione.
#
# Regola di questo script: se il backup non e' verificabile, ESCE CON ERRORE.
# Un backup che si dichiara riuscito senza esserlo e' peggio di nessun backup:
# ti fa procedere con la ri-autenticazione credendo di avere una rete che non c'e'.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TIENI="${TIENI:-10}"   # quanti backup conservare

richiede gcloud curl jq || exit 1
# Nessun ADC non e' un guasto: e' il primo collegamento. Distinguere i due casi
# conta, perche' uscire in errore qui lascia chi parte da zero senza una strada.
if [ ! -f "$ADC_FILE" ]; then
  echo "Nessuna credenziale da salvare: $ADC_FILE non esiste."
  echo
  echo "E' il primo collegamento su questa macchina, quindi non c'e' niente da"
  echo "perdere e niente da copiare. Puoi autenticarti direttamente:"
  echo "  bash \"$(dirname "$0")/comando-login.sh\" <scope-che-ti-serve>"
  echo
  echo "Dalla prossima volta questo backup servira': rilancialo prima di ogni"
  echo "nuova autorizzazione."
  exit 0
fi

mkdir -p "$BACKUP_DIR" || { err "ERRORE: impossibile creare $BACKUP_DIR"; exit 1; }
chmod 700 "$BACKUP_DIR"

TS=$(date +%Y%m%d-%H%M%S)
DEST="$BACKUP_DIR/adc-$TS.json"

# Il timestamp ha la risoluzione del secondo: due esecuzioni ravvicinate (o una
# automatizzata) ricadrebbero sullo stesso nome e la seconda sovrascriverebbe il
# punto di rollback della prima — cioe' proprio lo stato precedente che si
# voleva conservare. Si aggiunge un progressivo invece di sovrascrivere.
if [ -e "$DEST" ]; then
  N=2
  while [ -e "$BACKUP_DIR/adc-$TS-$N.json" ]; do N=$((N+1)); done
  DEST="$BACKUP_DIR/adc-$TS-$N.json"
fi

# --- 1. Copia, verificata davvero ---------------------------------------
cp -p "$ADC_FILE" "$DEST" || { err "ERRORE: copia fallita verso $DEST"; exit 1; }
chmod 600 "$DEST"        || { err "ERRORE: impossibile mettere in sicurezza $DEST"; rm -f "$DEST"; exit 1; }

if [ ! -s "$DEST" ] || ! cmp -s "$ADC_FILE" "$DEST"; then
  err "ERRORE: il backup non corrisponde all'originale. Rimosso."
  rm -f "$DEST"; exit 1
fi

# --- 2. Scope: se non si leggono, il backup NON e' completo --------------
# Gli scope non sono dentro il file ADC: esistono solo interrogando il token.
# Senza di essi non puoi ricostruire il comando di login, che e' il motivo
# per cui stai facendo il backup. Quindi qui un fallimento e' un errore, non una nota.
SCOPES_FILE="${DEST%.json}.scopes.txt"

backup_parziale(){ # un solo posto per l'uscita "credenziali si', scope no"
  err ""
  err "ATTENZIONE: credenziali copiate, ma gli scope NON sono stati registrati."
  err "  Motivo: $1"
  err "  Il file c'e' ($DEST) e il rollback funziona,"
  err "  ma non hai la lista scope per ricostruire il comando di login."
  err "  Risolvi prima di ri-autenticarti: scripts/comando-login.sh"
  echo
  echo "Backup parziale: $DEST"
  exit 2
}

if SCOPES=$(adc_scopes); then
  # La scrittura non si da' per riuscita perche' il comando precedente lo era:
  # disco pieno, permessi, filesystem in sola lettura falliscono QUI, e un
  # "Backup verificato" stampato comunque sarebbe la bugia peggiore di tutte
  # — e' l'unico motivo per cui questo script esiste.
  if ! ( printf '%s\n' "$SCOPES" > "$SCOPES_FILE" ) 2>/dev/null; then
    rm -f "$SCOPES_FILE" 2>/dev/null
    backup_parziale "scrittura di $SCOPES_FILE non riuscita (spazio su disco? permessi?)"
  fi
  if ! chmod 600 "$SCOPES_FILE" 2>/dev/null; then
    rm -f "$SCOPES_FILE" 2>/dev/null
    backup_parziale "impossibile mettere in sicurezza $SCOPES_FILE (restava leggibile ad altri)"
  fi
  # Rilettura: il file e' buono se contiene tutti gli scope, non se esiste.
  ATTESI=$(printf '%s\n' $SCOPES | grep -c .)
  SCRITTI=$(grep -c . "$SCOPES_FILE" 2>/dev/null || echo 0)
  if [ "$SCRITTI" != "$ATTESI" ]; then
    rm -f "$SCOPES_FILE" 2>/dev/null
    backup_parziale "scritti $SCRITTI scope su $ATTESI: file troncato"
  fi
  echo "Scope registrati al momento del backup ($ATTESI):"
  printf '  - %s\n' $SCOPES
else
  backup_parziale "gli scope non sono leggibili dal token attivo"
fi

# --- 3. Rotazione -------------------------------------------------------
# Ogni backup contiene un refresh token TUTTORA VALIDO: accumularli
# indefinitamente moltiplica le credenziali a lunga vita ferme su disco.
# Ordinamento per NOME, non per data: `cp -p` preserva il mtime dell'originale,
# quindi tutti i backup ereditano la stessa data e `ls -t` li ordinerebbe in modo
# arbitrario — arrivando a cancellare il piu' recente e tenere i vecchi.
# Il nome contiene gia' il timestamp (adc-AAAAMMGG-HHMMSS), quindi l'ordine
# alfabetico inverso e' l'ordine cronologico inverso.
# Il backup appena creato ($DEST) e' escluso in modo esplicito: non deve mai
# poter finire tra i candidati alla rimozione.
# NB: niente mapfile — su macOS /bin/bash e' la 3.2, dove non esiste.
VECCHI=()
while IFS= read -r v; do
  [ -n "$v" ] && [ "$v" != "$DEST" ] && VECCHI+=("$v")
done < <(ls -1 "$BACKUP_DIR"/adc-*.json 2>/dev/null | sort -r | tail -n +$((TIENI+1)))

if [ ${#VECCHI[@]} -gt 0 ]; then
  echo
  echo "Rotazione: rimuovo ${#VECCHI[@]} backup oltre i piu' recenti ($TIENI):"
  for v in "${VECCHI[@]}"; do
    echo "  - $(basename "$v")"
    rm -f "$v" "${v%.json}.scopes.txt"
  done
  echo "  Nota: cancellare il file NON revoca il refresh token lato Google."
  echo "  Per revocarli davvero: https://myaccount.google.com/permissions"
fi

echo
echo "Backup verificato: $DEST"
echo "Rollback:  cp -p \"$DEST\" \"$ADC_FILE\""
