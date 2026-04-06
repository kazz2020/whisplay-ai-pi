#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_FILE="${PROJECT_ROOT}/.env"

get_env_value() {
  local key="$1"
  if [ ! -f "${ENV_FILE}" ]; then
    return 0
  fi
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "${ENV_FILE}"; then
    local val
    val=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${ENV_FILE}" | tail -n1 | cut -d'=' -f2-)
    echo "$(echo "${val}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
  fi
}

PHRASE="${WAKE_WORD_PHRASE:-$(get_env_value WAKE_WORD_PHRASE)}"
REFERENCE_DIR="${WAKE_WORD_REFERENCE_DIR:-$(get_env_value WAKE_WORD_REFERENCE_DIR)}"
LOCAL_WAKE_BIN="${WAKE_WORD_LOCAL_WAKE_BIN:-$(get_env_value WAKE_WORD_LOCAL_WAKE_BIN)}"
LOCAL_WAKE_BIN="${LOCAL_WAKE_BIN:-lwake}"
SAMPLE_COUNT="${1:-${WAKE_WORD_SAMPLE_COUNT:-4}}"
SAMPLE_DURATION="${2:-${WAKE_WORD_SAMPLE_DURATION:-3}}"

normalize_positive_int() {
  local raw_value="$1"
  local fallback="$2"
  python3 - <<PY
import math

raw = ${raw_value@Q}.strip()
fallback = ${fallback@Q}.strip()

try:
    value = int(math.ceil(float(raw)))
    if value < 1:
        raise ValueError
except Exception:
    value = int(float(fallback))

print(value)
PY
}

SAMPLE_COUNT=$(normalize_positive_int "${SAMPLE_COUNT}" "4")
SAMPLE_DURATION=$(normalize_positive_int "${SAMPLE_DURATION}" "3")

if ! command -v "${LOCAL_WAKE_BIN}" >/dev/null 2>&1; then
  echo "local-wake binary '${LOCAL_WAKE_BIN}' was not found. Install wake word dependencies first." >&2
  exit 1
fi

if [ -z "${PHRASE}" ]; then
  read -r -p "Wake phrase label [hey whisplay] " PHRASE
  PHRASE="${PHRASE:-hey whisplay}"
fi

if [ -z "${REFERENCE_DIR}" ]; then
  SLUG=$(printf '%s' "${PHRASE}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  REFERENCE_DIR="${PROJECT_ROOT}/data/wakewords/${SLUG}"
fi

mkdir -p "${REFERENCE_DIR}"

if compgen -G "${REFERENCE_DIR}/*.wav" >/dev/null 2>&1; then
  read -r -p "Existing samples found in ${REFERENCE_DIR}. Replace them [Y/n] " REPLACE_REPLY
  REPLACE_REPLY="${REPLACE_REPLY:-Y}"
  case "${REPLACE_REPLY}" in
    y|Y|yes|YES)
      rm -f "${REFERENCE_DIR}"/*.wav
      ;;
  esac
fi

echo "Recording ${SAMPLE_COUNT} wake word samples for phrase: ${PHRASE}"
echo "Reference directory: ${REFERENCE_DIR}"

for index in $(seq 1 "${SAMPLE_COUNT}"); do
  echo
  echo "Sample ${index}/${SAMPLE_COUNT}"
  echo "When ready, press Enter and clearly say: ${PHRASE}"
  read -r
  "${LOCAL_WAKE_BIN}" record "${REFERENCE_DIR}/sample-${index}.wav" --duration "${SAMPLE_DURATION}"
done

echo
echo "Wake word samples saved in ${REFERENCE_DIR}"
echo "If detection is too sensitive or too weak, adjust WAKE_WORD_THRESHOLD in .env and restart the assistant."