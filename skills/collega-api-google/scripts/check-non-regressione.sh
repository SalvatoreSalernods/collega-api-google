#!/bin/bash
# Verifica che una ri-autenticazione non abbia tolto accessi che c'erano prima.
#
# Il confronto e' col PASSATO, non con il presente: la domanda non e' "quali API
# rispondono adesso" ma "ho perso qualcosa rispetto a prima del login". La
# differenza non e' accademica — guardando solo il presente, uno scope svanito
# sembra un servizio che non usi, e il guasto peggiore passa per normalita'.
# Il "prima" e' la lista di scope che backup-adc.sh ha salvato accanto alle
# credenziali copiate.
#
# Exit code: 0 = nessuna perdita | 1 = REGRESSIONE o guasto di CREDENZIALI
#            2 = impossibile concludere, o anomalia che non riguarda le credenziali
#
# Se hai tolto uno scope DI PROPOSITO (regola del permesso minimo), dichiaralo:
#   RIMOSSI_ATTESI=tagmanager.publish bash check-non-regressione.sh
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

richiede gcloud curl jq || exit 1

ADS_VER="${ADS_VER:-v22}"
PROBLEMA_CREDENZIALI=0
ANOMALIA=0
VISTO_404=0
RIMOSSI_OK=""

# --- 1. Gli scope di adesso ---------------------------------------------
echo "=== SCOPE ATTUALI ==="
if SCOPES=$(adc_scopes); then
  printf '  - %s\n' $SCOPES
else
  err "Impossibile proseguire: senza token non si verifica nulla."
  exit 1
fi

# --- 2. Gli scope di prima, dal backup piu' recente ---------------------
BASELINE=$(ls -1 "$BACKUP_DIR"/adc-*.scopes.txt 2>/dev/null | sort -r | head -1)
SCOPES_PRIMA=""
if [ -n "$BASELINE" ] && [ -s "$BASELINE" ]; then
  SCOPES_PRIMA=$(grep . "$BASELINE")
fi

echo
echo "=== CONFRONTO COL PRIMA ==="
if [ -z "$SCOPES_PRIMA" ]; then
  echo "  Nessuna lista di riferimento: non trovo backup in $BACKUP_DIR"
  err "  ATTENZIONE: senza il 'prima' questo script NON puo' dire se hai perso"
  err "  qualcosa — puo' solo dire che le API interrogate rispondono adesso."
  err "  Per avere il riferimento la prossima volta: scripts/backup-adc.sh"
  ANOMALIA=1
else
  echo "  Riferimento: $(basename "$BASELINE") ($(printf '%s\n' $SCOPES_PRIMA | grep -c .) scope)"

  # Scope presenti prima e assenti adesso.
  PERSI=$(printf '%s\n' $SCOPES_PRIMA \
          | grep -vxF -f <(printf '%s\n' $SCOPES) 2>/dev/null || true)

  # Rimozioni dichiarate volontarie: forma breve o URL completo, separate da
  # virgola o spazio. Togliere un permesso di scrittura e' una scelta legittima
  # (e consigliata): va distinta da una perdita.
  if [ -n "${RIMOSSI_ATTESI:-}" ]; then
    ATTESI=$(printf '%s' "$RIMOSSI_ATTESI" | tr ',' ' ')
    for a in $ATTESI; do
      case "$a" in
        https://*) URL="$a" ;;
        *)         URL="https://www.googleapis.com/auth/$a" ;;
      esac
      PERSI=$(printf '%s\n' $PERSI | grep -vxF "$URL" || true)
      RIMOSSI_OK="$RIMOSSI_OK $URL"
      echo "  Rimozione dichiarata volontaria: $URL"
    done
  fi

  NUOVI=$(printf '%s\n' $SCOPES \
          | grep -vxF -f <(printf '%s\n' $SCOPES_PRIMA) 2>/dev/null || true)
  [ -n "$NUOVI" ] && printf '  + aggiunto: %s\n' $NUOVI

  if [ -n "$PERSI" ]; then
    printf '  - PERSO:   %s\n' $PERSI
    err ""
    err "  Questi scope c'erano prima e adesso non ci sono: e' la sovrascrittura"
    err "  che questo script esiste per intercettare. Gli strumenti che li usavano"
    err "  hanno smesso di funzionare, anche se non te ne sei accorto."
    PROBLEMA_CREDENZIALI=1
  else
    echo "  Nessuno scope perso."
  fi
fi

# --- 3. Sonde sulle API ------------------------------------------------
# Si interrogano le API autorizzate PRIMA o ADESSO: unione, non intersezione.
# Se un'API funzionava prima e adesso non e' piu' autorizzata, va interrogata
# proprio per mostrare il danno — saltarla lo nasconderebbe.
SCOPES_ATTESI=$(printf '%s\n' $SCOPES $SCOPES_PRIMA | sed '/^$/d' | sort -u)
if [ -n "$RIMOSSI_OK" ]; then
  # Un accesso ritirato di proposito non va piu' interrogato: il suo 403 e'
  # il risultato voluto, non un guasto.
  SCOPES_ATTESI=$(printf '%s\n' $SCOPES_ATTESI \
                  | grep -vxF -f <(printf '%s\n' $RIMOSSI_OK) 2>/dev/null || true)
fi

ha_uno_di(){ # confronto ESATTO con gli scope che autorizzano quella chiamata
  local sc
  for sc in "$@"; do
    printf '%s\n' $SCOPES_ATTESI | grep -qx "https://www.googleapis.com/auth/$sc" && return 0
  done
  return 1
}

TOK=$(adc_token) || exit 1

check(){ # nome, url, [header extra]
  # Un 403 non e' automaticamente un guasto di credenziali: lo e' solo se Google
  # dice che mancano gli scope. API disabilitata, account senza accesso al
  # prodotto o developer token non valido rispondono anch'essi 403, e in quei
  # casi un rollback annullerebbe un ADC sano per una causa che sta altrove.
  local name="$1" url="$2" resp code body motivo
  if [ $# -ge 3 ] && [ -n "$3" ]; then
    resp=$(curl -s --max-time 25 -w $'\n%{http_code}' \
             -H "Authorization: Bearer $TOK" -H "$3" "$url")
  else
    resp=$(curl -s --max-time 25 -w $'\n%{http_code}' \
             -H "Authorization: Bearer $TOK" "$url")
  fi
  code=$(printf '%s' "$resp" | tail -1)
  body=$(printf '%s' "$resp" | sed '$d')

  case "$code" in
    200) printf "  OK    %-14s (200)\n" "$name" ;;
    401)
      printf "  KO    %-14s (401)  <-- CREDENZIALI\n" "$name"
      PROBLEMA_CREDENZIALI=1 ;;
    403)
      if printf '%s' "$body" | grep -qiE 'ACCESS_TOKEN_SCOPE_INSUFFICIENT|insufficient authentication scopes|insufficient_scope|invalid authentication credentials'; then
        printf "  KO    %-14s (403)  <-- CREDENZIALI: scope mancante\n" "$name"
        PROBLEMA_CREDENZIALI=1
      else
        motivo=$(printf '%s' "$body" | jq -r '.error.message // .error.status // empty' 2>/dev/null | head -1)
        printf "  ATT.  %-14s (403)  permessi, NON scope: nessun rollback da fare\n" "$name"
        [ -n "$motivo" ] && printf "        Google dice: %s\n" "$(printf '%s' "$motivo" | cut -c1-120)"
        printf "        Cause tipiche: API disabilitata sul progetto, account non invitato\n"
        printf "        alla risorsa, developer token non valido.\n"
        ANOMALIA=1
      fi ;;
    404)
      printf "  ATT.  %-14s (404)  endpoint inesistente, NON e' un problema di credenziali\n" "$name"
      VISTO_404=1
      ANOMALIA=1 ;;
    000)
      printf "  ATT.  %-14s (---)  nessuna risposta: rete o timeout\n" "$name"
      ANOMALIA=1 ;;
    *)
      printf "  ATT.  %-14s (%s)  da verificare\n" "$name" "$code"
      ANOMALIA=1 ;;
  esac
}

echo
echo "=== RAGGIUNGIBILITA' API ==="
ESEGUITI=0

if ha_uno_di adwords; then
  if DEV=$(dev_token); then
    check "Google Ads" "https://googleads.googleapis.com/$ADS_VER/customers:listAccessibleCustomers" "developer-token: $DEV"
    ESEGUITI=$((ESEGUITI+1))
  else
    printf "  SALTATO  %-14s scope presente ma developer token non trovato\n" "Google Ads"
    err "  (impostalo in GOOGLE_ADS_DEVELOPER_TOKEN, nel config della skill o in ~/.claude.json)"
    ANOMALIA=1
  fi
else
  printf "  --       %-14s non autorizzato (mai presente, o rimosso di proposito): salto\n" "Google Ads"
fi

if ha_uno_di analytics.readonly analytics.edit; then
  check "GA4 Admin" "https://analyticsadmin.googleapis.com/v1beta/accountSummaries?pageSize=1"
  ESEGUITI=$((ESEGUITI+1))
else
  printf "  --       %-14s nessuno scope che autorizzi accountSummaries: salto\n" "GA4 Admin"
fi

if ha_uno_di tagmanager.readonly tagmanager.manage.accounts tagmanager.manage.users \
             tagmanager.edit.containers tagmanager.edit.containerversions tagmanager.publish; then
  check "Tag Manager" "https://tagmanager.googleapis.com/tagmanager/v2/accounts"
  ESEGUITI=$((ESEGUITI+1))
else
  printf "  --       %-14s nessuno scope che autorizzi accounts.list: salto\n" "Tag Manager"
fi

if [ "$ESEGUITI" = "0" ]; then
  echo
  err "ATTENZIONE: nessuna API verificata — nessuno degli scope noti a questo"
  err "  script e' mai stato presente. Non e' una conferma che tutto funzioni:"
  err "  e' l'assenza di una verifica. Prova a mano l'endpoint che ti interessa."
  ANOMALIA=1
fi

# --- 4. Verdetto -------------------------------------------------------
echo
if [ "$PROBLEMA_CREDENZIALI" = "1" ]; then
  err "ESITO: REGRESSIONE o guasto di CREDENZIALI."
  err "Torna indietro dal backup piu' recente PRIMA di continuare a lavorare:"
  err "  ls -1 $BACKUP_DIR/adc-*.json | sort -r | head -1"
  err "  cp -p <quel-file> $ADC_FILE"
  err "Poi rifai il login con la lista COMPLETA: scripts/comando-login.sh"
  [ -n "${RIMOSSI_ATTESI:-}" ] || err "Se una rimozione era voluta: RIMOSSI_ATTESI=<scope> bash \"$0\""
  exit 1
elif [ "$ANOMALIA" = "1" ]; then
  echo "ESITO: nessuna perdita di scope, ma qualcosa merita un'occhiata."
  if [ "$VISTO_404" = "1" ]; then
    echo "Se il 404 e' su Google Ads, prova una versione piu' recente:"
    echo "  ADS_VER=v23 bash \"$0\""
  fi
  exit 2
else
  echo "ESITO: nessuno scope perso e tutte le API attese rispondono."
  exit 0
fi
