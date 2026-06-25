#!/usr/bin/env bash
# =============================================================================
# Recherche d'une instance Oracle Always Free (ARM) — version CLOUD (GitHub Actions).
# Une "passe" de MAX_DURATION secondes : à chaque tour essaie 2 OCPU/12 Go puis
# 1 OCPU/6 Go, jusqu'au succès ou expiration. Le cron GitHub relance une passe
# toutes les ~10 min. Au succès : notifie iPhone (ntfy) + email, et signale
# l'IP au workflow (qui pose un drapeau FOUND.flag pour stopper les futures passes).
# =============================================================================
set -uo pipefail

OCI="$(command -v oci)"
[ -z "$OCI" ] && { echo "ERREUR: oci CLI introuvable"; exit 1; }

COMPARTMENT="${OCI_COMPARTMENT:?OCI_COMPARTMENT manquant}"
SUBNET="${OCI_SUBNET:?OCI_SUBNET manquant}"
PUBKEY="$HOME/.oci/ssh_pub.pub"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:?NTFY_TOPIC manquant}"
NTFY_EMAIL="${NTFY_EMAIL:-}"
SHAPE="VM.Standard.A1.Flex"
NAME="${VM_NAME:-trainova-test}"
MAX_DURATION="${MAX_DURATION:-280}"
SLEEP_SECONDS="${SLEEP_SECONDS:-20}"
SIZES=("2:12" "1:6")
START_TS="$(date +%s)"

ts(){ date '+%Y-%m-%d %H:%M:%S'; }
out(){ [ -n "${GITHUB_OUTPUT:-}" ] && echo "$1=$2" >> "$GITHUB_OUTPUT"; }
notify(){ # <titre> <priorité> <tags> <message>
  curl -s --max-time 20 -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
    ${NTFY_EMAIL:+-H "Email: $NTFY_EMAIL"} \
    -d "$4" "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null 2>&1 || true
}

[ -f "$PUBKEY" ] || { echo "ERREUR: clé publique SSH absente ($PUBKEY)"; exit 1; }

AD="$("$OCI" iam availability-domain list --compartment-id "$COMPARTMENT" --query 'data[0].name' --raw-output 2>/dev/null)"
if [ -z "$AD" ] || [ "$AD" = "None" ]; then echo "[$(ts)] ERREUR: Availability Domain introuvable (auth OCI ?)."; exit 1; fi

IMAGE="$("$OCI" compute image list --compartment-id "$COMPARTMENT" \
  --operating-system 'Canonical Ubuntu' --operating-system-version '22.04' \
  --shape "$SHAPE" --sort-by TIMECREATED --sort-order DESC \
  --query "data[?contains(\"display-name\", 'aarch64') && !contains(\"display-name\", 'Minimal')].id | [0]" \
  --raw-output 2>/dev/null)"
if [ -z "$IMAGE" ] || [ "$IMAGE" = "None" ]; then
  IMAGE="$("$OCI" compute image list --compartment-id "$COMPARTMENT" \
    --operating-system 'Canonical Ubuntu' --operating-system-version '22.04' \
    --shape "$SHAPE" --sort-by TIMECREATED --sort-order DESC \
    --query 'data[0].id' --raw-output 2>/dev/null)"
fi
if [ -z "$IMAGE" ] || [ "$IMAGE" = "None" ]; then echo "[$(ts)] ERREUR: image Ubuntu 22.04 ARM introuvable."; exit 1; fi

try_one(){ # <ocpus> <mem> -> 0 succès / 2 réessayer / 1 fatal
  local ocpus="$1" mem="$2" err inst_id rc st ip
  echo "[$(ts)]   → essai ${ocpus} OCPU / ${mem} Go…"
  err="$(mktemp)"
  inst_id="$("$OCI" compute instance launch \
      --availability-domain "$AD" --compartment-id "$COMPARTMENT" \
      --shape "$SHAPE" --shape-config "{\"ocpus\":${ocpus},\"memoryInGBs\":${mem}}" \
      --image-id "$IMAGE" --subnet-id "$SUBNET" --assign-public-ip true \
      --display-name "$NAME" --ssh-authorized-keys-file "$PUBKEY" \
      --query 'data.id' --raw-output 2>"$err")"; rc=$?

  if [ $rc -eq 0 ] && [ -n "$inst_id" ] && [ "$inst_id" != "None" ]; then
    echo "[$(ts)] ✅ acceptée (${ocpus}/${mem}) : $inst_id — attente RUNNING…"
    for _ in $(seq 1 60); do
      st="$("$OCI" compute instance get --instance-id "$inst_id" --query 'data."lifecycle-state"' --raw-output 2>/dev/null)"
      [ "$st" = "RUNNING" ] && break
      case "$st" in TERMINATED|TERMINATING|FAILED) echo "[$(ts)] état=$st"; rm -f "$err"; return 1;; esac
      sleep 8
    done
    ip="$("$OCI" compute instance list-vnics --instance-id "$inst_id" --query 'data[0]."public-ip"' --raw-output 2>/dev/null)"
    out found true; out ip "$ip"; out ocid "$inst_id"
    notify "🟢 ORACLE VM ▸ IP PRÊTE" "high" "white_check_mark,rocket" \
      "[Trainova/Oracle] Instance ${NAME} créée — ${ocpus} OCPU/${mem} Go. IP=${ip}. Connexion: ssh ubuntu@${ip}"
    echo "[$(ts)] 🎉 SUCCÈS (${ocpus}/${mem}) IP=${ip} OCID=${inst_id}"
    rm -f "$err"; return 0
  fi

  if grep -qiE 'Out of host capacity|InternalError|TooManyRequests|ServiceUnavailable|"status": *(429|500|503)|Connection|Timed out|timeout|Max retries|Could not connect|temporarily' "$err"; then
    echo "[$(ts)]   ✗ ${ocpus}/${mem} indisponible (capacité)."; rm -f "$err"; return 2
  elif [ ! -s "$err" ]; then
    echo "[$(ts)]   ✗ ${ocpus}/${mem} échec sans détail (transitoire)."; rm -f "$err"; return 2
  else
    echo "[$(ts)] ❌ ERREUR NON liée à la capacité (${ocpus}/${mem}) :"; cat "$err"
    notify "🔴 ORACLE VM ▸ ARRÊT" "high" "warning" \
      "[Trainova/Oracle] Erreur NON liée à la capacité (${ocpus}/${mem} Go). Voir les logs GitHub Actions."
    rm -f "$err"; return 1
  fi
}

echo "[$(ts)] Passe de ${MAX_DURATION}s — AD=$AD — ordre: 2 OCPU/12 Go → 1 OCPU/6 Go"
while [ $(( $(date +%s) - START_TS )) -lt "$MAX_DURATION" ]; do
  for size in "${SIZES[@]}"; do
    try_one "${size%%:*}" "${size##*:}"; rc=$?
    [ "$rc" -eq 0 ] && exit 0
    [ "$rc" -eq 1 ] && exit 1
  done
  sleep "$SLEEP_SECONDS"
done
echo "[$(ts)] Pas de capacité durant cette passe — la prochaine planification réessaiera."
exit 0
