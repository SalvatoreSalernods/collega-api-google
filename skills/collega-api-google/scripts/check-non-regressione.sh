#!/bin/bash
# Verifica che l'ADC funzioni ancora per TUTTI gli MCP Google configurati.
# Da eseguire dopo ogni ri-autenticazione.
#
# Exit code: 0 = tutto a posto | 1 = problema di CREDENZIALI (fai rollback)
#            2 = anomalia che NON riguarda le credenziali (es. versione API morta)
# Serve perche' uno script di guardia deve poter fermare una catena,
# non limitarsi a scrivere "KO" a schermo.
set -u
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

richiede gcloud curl jq || exit 1

# Versione API Google Ads: sovrascrivibile senza toccare lo script, perche'
# Google deprecca le versioni ogni ~anno e un 404 qui sembra un guasto di credenziali.
ADS_VER="${ADS_VER:-v22}"

echo "=== SCOPE PRESENTI ==="
if SCOPES=$(adc_scopes); then
  printf '  - %s\n' $SCOPES
else
  err "Impossibile proseguire: senza token non si verifica nulla."
  exit 1
fi

TOK=$(adc_token) || exit 1
PROBLEMA_CREDENZIALI=0
ANOMALIA=0
VISTO_404=0

echo
echo "=== RAGGIUNGIBILITA' API ==="

check(){ # nome, url, [header extra]
  # Un 403 non e' automaticamente un problema di credenziali: lo e' solo se Google
  # dice che mancano gli scope. Un'API disabilitata, un account senza accesso al
  # prodotto o un developer token non valido rispondono anch'essi 403 — e
  # consigliare un rollback in quei casi significa far annullare all'utente un ADC
  # sano per una causa che sta altrove. E' la stessa distinzione che la skill
  # pretende dagli errori di Google: qui va rispettata, non solo predicata.
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
        # Si stampa il messaggio di Google, non il corpo grezzo.
        motivo=$(printf '%s' "$body" | jq -r '.error.message // .error.status // empty' 2>/dev/null | head -1)
        printf "  ATT.  %-14s (403)  permessi, NON scope: nessun rollback da fare\n" "$name"
        [ -n "$motivo" ] && printf "        Google dice: %s\n" "$(printf '%s' "$motivo" | cut -c1-120)"
        printf "        Cause tipiche: API disabilitata sul progetto, account non invitato\n"
        printf "        alla risorsa, developer token non valido.\n"
        ANOMALIA=1
      fi ;;
    404)
      # Un 404 non e' un problema di permessi: e' un endpoint che non esiste
      # (tipicamente una versione di API dismessa). Distinguerlo evita
      # un rollback delle credenziali per una causa che non c'entra.
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

# Si interrogano SOLO le API per cui lo scope e' presente. Senza questo filtro,
# chi usa un sottoinsieme delle integrazioni (solo Search Console, per esempio)
# riceverebbe un 403 su Tag Manager e leggerebbe "problema di credenziali, fai
# rollback" dopo una ri-autenticazione perfettamente riuscita: il guardiano
# direbbe di annullare proprio il lavoro appena fatto bene.
# Il confronto e' ESATTO e per endpoint, non per prefisso di prodotto: avere un
# qualsiasi scope della famiglia "analytics" non autorizza accountSummaries
# (analytics.manage.users.readonly, per esempio, riceverebbe 403), e quel 403
# verrebbe letto come regressione da annullare. Si elencano gli scope che
# autorizzano davvero la chiamata di prova.
ha_uno_di(){
  local sc
  for sc in "$@"; do
    printf '%s\n' $SCOPES | grep -qx "https://www.googleapis.com/auth/$sc" && return 0
  done
  return 1
}
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
  printf "  --       %-14s scope 'adwords' assente: non lo usi, salto\n" "Google Ads"
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

# Un controllo che non ha controllato niente non puo' dire "nessuna regressione".
if [ "$ESEGUITI" = "0" ]; then
  echo
  err "ATTENZIONE: nessuna API verificata — nessuno degli scope noti e' presente."
  err "  Non e' una conferma che tutto funzioni: e' l'assenza di una verifica."
  err "  Prova a mano l'endpoint dell'API che ti interessa (passo 1 della skill)."
  ANOMALIA=1
fi

echo
if [ "$PROBLEMA_CREDENZIALI" = "1" ]; then
  err "ESITO: problema di CREDENZIALI."
  err "Fai rollback dal backup piu' recente PRIMA di continuare a lavorare:"
  err "  ls -1t $BACKUP_DIR/adc-*.json | head -1"
  err "  cp -p <quel-file> $ADC_FILE"
  exit 1
elif [ "$ANOMALIA" = "1" ]; then
  echo "ESITO: nessun problema di credenziali, ma qualcosa merita un'occhiata."
  # Il suggerimento sulla versione si dà solo se un 404 c'è stato davvero:
  # altrimenti indirizza verso una causa che non c'entra con quel che è successo.
  if [ "$VISTO_404" = "1" ]; then
    echo "Se il 404 e' su Google Ads, prova una versione piu' recente:"
    echo "  ADS_VER=v23 bash \"$0\""
  fi
  exit 2
else
  echo "ESITO: tutte le API rispondono. Nessuna regressione."
  exit 0
fi
