#!/bin/bash
# Funzioni condivise dagli script della skill collega-api-google.
# Da sorgere, non da eseguire:  source "$(dirname "$0")/lib.sh"
#
# Principio: ogni funzione o restituisce un dato valido, o fallisce rumorosamente.
# Un token o una lista di scope "parziali" sono piu' pericolosi di un errore:
# e' da li' che nasce il login che cancella gli scope degli altri MCP.

# --- Configurazione locale ----------------------------------------------
# I dati specifici dell'utente (progetto Google Cloud, file client OAuth) NON
# stanno in questi script: la skill si pubblica, il config no. Se il file non
# esiste, gli script lo dicono e rimandano a configura.sh.
CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/collega-api-google}"
CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/config.env}"
# shellcheck disable=SC1090
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# gcloud legge e RISCRIVE l'ADC sotto CLOUDSDK_CONFIG quando la variabile e'
# impostata. Ignorarla significherebbe salvaguardare un file che gcloud non
# tocca: il backup riuscirebbe e proteggerebbe credenziali diverse da quelle
# che il login sta per sovrascrivere — il caso peggiore, perche' silenzioso.
GCLOUD_DIR="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"
ADC_FILE="${ADC_FILE:-$GCLOUD_DIR/application_default_credentials.json}"
BACKUP_DIR="${BACKUP_DIR:-$GCLOUD_DIR/backups}"

err(){ printf '%s\n' "$*" >&2; }

shell_quote(){ # stampa $1 quotato in modo che una shell lo rilegga identico
  # Serve in due punti: quando si SCRIVE il config (che viene sorgente) e quando
  # si STAMPA un comando che una persona incollera' nel terminale. Un percorso
  # legittimo con $ ` " o backslash — ammessi nei nomi di file su macOS e Linux —
  # altrimenti viene espanso dalla shell e punta a un file che non esiste.
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

manca_config(){ # messaggio unico: un solo posto da cambiare
  err "ERRORE: $1 non e' configurato."
  err "  Eseguilo una volta sola:  bash \"$(dirname "${BASH_SOURCE[0]}")/configura.sh\""
  err "  I valori finiscono in $CONFIG_FILE (fuori dalla cartella della skill)."
}

richiede(){ # verifica le dipendenze prima di partire
  local mancanti=()
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || mancanti+=("$c"); done
  if [ ${#mancanti[@]} -gt 0 ]; then
    err "ERRORE: comandi mancanti: ${mancanti[*]}"
    return 1
  fi
}

project_id(){ # stampa il project ID Google Cloud, oppure fallisce
  if [ -z "${GCP_PROJECT_ID:-}" ]; then
    manca_config "il progetto Google Cloud (GCP_PROJECT_ID)"
    return 1
  fi
  printf '%s' "$GCP_PROJECT_ID"
}

adc_token(){ # stampa un access token valido, oppure fallisce
  local t
  t=$(gcloud auth application-default print-access-token 2>/dev/null) || true
  if [ -z "$t" ] || [ ${#t} -lt 50 ]; then
    err "ERRORE: nessun access token valido dall'ADC."
    err "  L'ADC potrebbe essere assente, scaduto o revocato: $ADC_FILE"
    return 1
  fi
  printf '%s' "$t"
}

adc_scopes(){ # stampa gli scope attivi, uno per riga, oppure fallisce
  # Il token va nel BODY della POST, non in query string: un access token
  # nell'URL finisce nei log dei server e degli eventuali proxy.
  local tok resp scope motivo
  tok=$(adc_token) || return 1
  resp=$(curl -s --max-time 20 -X POST -d "access_token=$tok" \
           "https://oauth2.googleapis.com/tokeninfo") || {
    err "ERRORE: chiamata a tokeninfo fallita (rete?)."; return 1; }

  scope=$(printf '%s' "$resp" | jq -r '.scope // empty' 2>/dev/null)
  if [ -z "$scope" ]; then
    # Si stampa SOLO il motivo dichiarato da Google, mai la risposta grezza:
    # quando la chiamata va a buon fine il corpo contiene anche email e client
    # ID, che non devono finire in un output copiabile in una issue pubblica.
    motivo=$(printf '%s' "$resp" \
      | jq -r '[.error_description, (.error|strings), (.error|objects|.message)] | map(select(type == "string")) | first // empty' 2>/dev/null)
    err "ERRORE: impossibile leggere gli scope dal token."
    if [ -n "$motivo" ]; then
      err "  Motivo riferito da Google: $motivo"
    else
      err "  Google ha risposto senza un motivo leggibile (token valido ma senza scope?)."
      err "  Per ispezionare la risposta a mano — attenzione, contiene la tua email:"
      err "    gcloud auth application-default print-access-token | xargs -I T curl -s -X POST -d access_token=T https://oauth2.googleapis.com/tokeninfo"
    fi
    return 1
  fi
  printf '%s\n' $scope | sort
}

glob_lista(){ # espande un percorso che puo' contenere un glob E degli spazi
  # Un glob va lasciato non quotato per essere espanso, ma senza quote bash lo
  # spezza anche sugli spazi: "Google Cloud/x_*.json" diventerebbe due parole e
  # non troverebbe nulla. Azzerando IFS ai soli ritorni a capo, lo spazio non
  # e' piu' un separatore e il glob funziona comunque.
  local pattern="$1" oldifs="$IFS"
  IFS=$'\n'
  ls -1 -d -- $pattern 2>/dev/null
  IFS="$oldifs"
}

client_file(){ # stampa il percorso del file client OAuth, oppure fallisce
  local pattern trovati n
  pattern="${OAUTH_CLIENT_FILE:-}"
  if [ -z "$pattern" ]; then
    manca_config "il file del client OAuth (OAUTH_CLIENT_FILE)"
    return 1
  fi

  # Il valore puo' essere un percorso esatto o contenere un glob: si accettano
  # entrambi, ma un glob che pesca piu' di un file e' un'ambiguita', non una scelta.
  trovati=$(glob_lista "$pattern")
  n=$(printf '%s' "$trovati" | grep -c . )
  if [ "$n" = "0" ]; then
    err "ERRORE: nessun file client OAuth corrisponde a: $pattern"
    err "  Se l'hai spostato, aggiorna $CONFIG_FILE (o rilancia configura.sh)."
    return 1
  elif [ "$n" != "1" ]; then
    err "ERRORE: trovati $n file corrispondenti a $pattern — ambiguo, indica quale usare."
    printf '%s\n' "$trovati" >&2
    return 1
  fi
  printf '%s' "$trovati"
}

dev_token(){ # developer token Google Ads: da env/config, altrimenti dalla config MCP.
  # Non va MAI scritto nel sorgente di uno script: le skill si condividono.
  if [ -n "${GOOGLE_ADS_DEVELOPER_TOKEN:-}" ]; then
    printf '%s' "$GOOGLE_ADS_DEVELOPER_TOKEN"; return 0
  fi
  local t
  t=$(jq -r '.mcpServers."google-ads-mcp".env.GOOGLE_ADS_DEVELOPER_TOKEN // empty' \
        "$HOME/.claude.json" 2>/dev/null)
  [ -n "$t" ] && { printf '%s' "$t"; return 0; }
  return 1
}
