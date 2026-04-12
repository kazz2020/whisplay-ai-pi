#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${1:-${PROJECT_ROOT}/.env}"

if [ -t 1 ]; then
  COLOR_RESET=$(printf '\033[0m')
  COLOR_BOLD=$(printf '\033[1m')
  COLOR_DIM=$(printf '\033[2m')
  COLOR_RED=$(printf '\033[31m')
  COLOR_GREEN=$(printf '\033[32m')
  COLOR_YELLOW=$(printf '\033[33m')
  COLOR_BLUE=$(printf '\033[34m')
  COLOR_CYAN=$(printf '\033[36m')
else
  COLOR_RESET=""
  COLOR_BOLD=""
  COLOR_DIM=""
  COLOR_RED=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BLUE=""
  COLOR_CYAN=""
fi

hr() {
  printf '%s%s%s\n' "${COLOR_DIM}" "================================================================" "${COLOR_RESET}"
}

section() {
  local title="$1"
  printf '\n'
  hr
  printf '%s%s%s\n' "${COLOR_BOLD}${COLOR_CYAN}" "${title}" "${COLOR_RESET}"
}

note() {
  local text="$1"
  printf '%s%s%s\n' "${COLOR_DIM}" "${text}" "${COLOR_RESET}"
}

status_line() {
  local label="$1"
  local value="$2"
  printf '  %s%-18s%s %s\n' "${COLOR_GREEN}" "${label}" "${COLOR_RESET}" "${value}"
}

info() {
  printf '%s[i]%s %s\n' "${COLOR_BLUE}" "${COLOR_RESET}" "$*"
}

warn() {
  printf '%s[!]%s %s\n' "${COLOR_YELLOW}" "${COLOR_RESET}" "$*" >&2
}

success() {
  printf '%s[ok]%s %s\n' "${COLOR_GREEN}" "${COLOR_RESET}" "$*"
}

die() {
  printf '%s[x]%s %s\n' "${COLOR_RED}" "${COLOR_RESET}" "$*" >&2
  exit 1
}

print_banner() {
  printf '\n'
  hr
  printf '%s%s%s\n' "${COLOR_BOLD}${COLOR_CYAN}" "Whisplay Ollama Model Switcher" "${COLOR_RESET}"
  printf '%s%s%s\n' "${COLOR_DIM}" "Switch the active Ollama model in .env without rerunning the full installer." "${COLOR_RESET}"
  hr
}

get_env_value() {
  local key="$1"

  if [ ! -f "${ENV_FILE}" ]; then
    return 1
  fi

  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "${ENV_FILE}"; then
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "${ENV_FILE}" | tail -n1 | cut -d'=' -f2- | \
      sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
  else
    return 1
  fi
}

set_env_value() {
  local key="$1"
  local value="$2"
  local temp_file

  temp_file=$(mktemp)
  awk -v key="${key}" -v value="${value}" '
    BEGIN { updated=0 }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      if (!updated) {
        print key "=" value
        updated=1
      }
      next
    }
    { print }
    END {
      if (!updated) {
        print key "=" value
      }
    }
  ' "${ENV_FILE}" > "${temp_file}"

  mv "${temp_file}" "${ENV_FILE}"
}

confirm() {
  local prompt="$1"
  local default_answer="${2:-n}"
  local reply

  if [ "${default_answer}" = "y" ]; then
    read -r -p "${prompt} [Y/n] " reply
    reply="${reply:-y}"
  else
    read -r -p "${prompt} [y/N] " reply
    reply="${reply:-n}"
  fi

  case "${reply}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

trim_value() {
  echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

fetch_models_from_endpoint() {
  local endpoint="$1"
  local api_key="$2"
  local response

  if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi

  if [ -z "${endpoint}" ]; then
    return 1
  fi

  if [ -n "${api_key}" ]; then
    response=$(curl -fsS --max-time 15 -H "Authorization: Bearer ${api_key}" "${endpoint%/}/api/tags" 2>/dev/null || true)
  else
    response=$(curl -fsS --max-time 15 "${endpoint%/}/api/tags" 2>/dev/null || true)
  fi

  if [ -z "${response}" ]; then
    return 1
  fi

  RESPONSE_JSON="${response}" python3 - <<'PY'
import json
import os

raw = os.environ.get("RESPONSE_JSON", "")
if not raw:
    raise SystemExit(1)

data = json.loads(raw)
models = []
for item in data.get("models", []):
    name = item.get("name") or item.get("model")
    if name and name not in models:
        models.append(name)

for model in models:
    print(model)
PY
}

print_presets() {
  cat <<'EOF'
glm-5.1:cloud|GLM 5.1 Cloud|General assistant default
gemma3:27b-cloud|Gemma 3 27B Cloud|General assistant default
gemma4:26b-cloud|Gemma 4 26B Cloud|Newer flagship-style general model
qwen3.5:27b-cloud|Qwen 3.5 27B Cloud|Strong multilingual assistant
qwen3-vl:30b-cloud|Qwen 3 VL 30B Cloud|Vision-capable model
devstral-small-2:24b-cloud|Devstral Small 2 24B Cloud|Coding-focused assistant
gpt-oss:120b-cloud|gpt-oss 120B Cloud|Large reasoning model
EOF
}

choose_option() {
  local max_value="$1"
  local choice

  while true; do
    read -r -p "Select option [1-${max_value}]: " choice
    if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${max_value}" ]; then
      printf '%s' "${choice}"
      return 0
    fi
    warn "Invalid choice. Enter a number from 1 to ${max_value}."
  done
}

render_model_menu() {
  local idx

  section "Available Models"
  note "Pick a preset below or enter a custom tag."
  for idx in "${!models[@]}"; do
    printf '  %s%2d)%s %-28s %s\n' "${COLOR_BOLD}${COLOR_CYAN}" "$((idx + 1))" "${COLOR_RESET}" "${labels[idx]}" "${descriptions[idx]}"
  done
  printf '  %s%2d)%s %s\n' "${COLOR_BOLD}${COLOR_CYAN}" "$(( ${#models[@]} + 1 ))" "${COLOR_RESET}" "Custom model tag"
}

if [ ! -f "${ENV_FILE}" ]; then
  die "Missing env file: ${ENV_FILE}"
fi

if [ ! -s "${ENV_FILE}" ]; then
  die "Env file is empty: ${ENV_FILE}"
fi

print_banner

current_llm_server=$(get_env_value "LLM_SERVER" || true)
current_endpoint=$(get_env_value "OLLAMA_ENDPOINT" || true)
current_model=$(get_env_value "OLLAMA_MODEL" || true)
current_api_key=$(get_env_value "OLLAMA_API_KEY" || true)
current_vision_server=$(get_env_value "VISION_SERVER" || true)

if [ -z "${current_endpoint}" ]; then
  current_endpoint="https://ollama.com"
fi

section "Current Configuration"
status_line "Env file" "${ENV_FILE}"
status_line "LLM server" "${current_llm_server:-unset}"
status_line "Endpoint" "${current_endpoint}"
status_line "Model" "${current_model:-unset}"
status_line "Vision" "${current_vision_server:-disabled}"

if [ "${current_llm_server}" != "ollama-cloud" ] && [ "${current_llm_server}" != "ollama" ]; then
  warn "Current LLM provider is not Ollama."
  if ! confirm "Switch LLM_SERVER to ollama-cloud and continue" "y"; then
    die "Aborted before changing provider."
  fi
  current_llm_server="ollama-cloud"
  set_env_value "LLM_SERVER" "ollama-cloud"
  success "LLM_SERVER updated to ollama-cloud."
fi

declare -a models=()
declare -a labels=()
declare -a descriptions=()
model_source="presets"

section "Discovering Models"
info "Checking ${current_endpoint%/}/api/tags"

while IFS= read -r model; do
  [ -n "${model}" ] || continue
  models+=("${model}")
  labels+=("${model}")
  descriptions+=("Available from the configured endpoint")
done < <(fetch_models_from_endpoint "${current_endpoint}" "${current_api_key}" || true)

if [ "${#models[@]}" -gt 0 ]; then
  model_source="endpoint"
  success "Loaded ${#models[@]} model entries from the endpoint."
else
  warn "Could not read model tags from the endpoint; falling back to curated presets."
  while IFS='|' read -r model label description; do
    [ -n "${model}" ] || continue
    models+=("${model}")
    labels+=("${label}")
    descriptions+=("${description}")
  done < <(print_presets)
fi

if [ -n "${current_model}" ]; then
  found_current=false
  for model in "${models[@]}"; do
    if [ "${model}" = "${current_model}" ]; then
      found_current=true
      break
    fi
  done
  if [ "${found_current}" = false ]; then
    models=("${current_model}" "${models[@]}")
    labels=("${current_model} (current)" "${labels[@]}")
    descriptions=("Currently configured model, kept visible for safety" "${descriptions[@]}")
  fi
fi

section "Source"
status_line "Model source" "${model_source}"
status_line "Entries" "${#models[@]}"

render_model_menu
custom_option=$(( ${#models[@]} + 1 ))
choice=$(choose_option "${custom_option}")

if [ "${choice}" -eq "${custom_option}" ]; then
  printf '\n'
  read -r -p "Enter the exact Ollama model tag: " selected_model
  selected_model=$(trim_value "${selected_model}")
  if [ -z "${selected_model}" ]; then
    die "Model tag cannot be empty."
  fi
  selected_label="${selected_model}"
else
  selected_model="${models[$((choice - 1))]}"
  selected_label="${labels[$((choice - 1))]}"
fi

section "Review Change"
status_line "Current model" "${current_model:-unset}"
status_line "New model" "${selected_model}"
status_line "Endpoint" "${current_endpoint}"

if ! confirm "Apply this model change" "y"; then
  die "No changes were written."
fi

set_env_value "OLLAMA_ENDPOINT" "${current_endpoint}"
set_env_value "OLLAMA_MODEL" "${selected_model}"
success "Updated OLLAMA_MODEL to ${selected_model}."

if [ "${current_vision_server}" = "ollama" ]; then
  current_vision_model=$(get_env_value "OLLAMA_VISION_MODEL" || true)
  if [ -z "${current_vision_model}" ] || [ "${current_vision_model}" = "${current_model}" ]; then
    if confirm "Also set OLLAMA_VISION_MODEL to ${selected_model}" "n"; then
      set_env_value "OLLAMA_VISION_MODEL" "${selected_model}"
      success "Updated OLLAMA_VISION_MODEL to ${selected_model}."
    fi
  else
    note "Skipping OLLAMA_VISION_MODEL because it already points to a different dedicated model."
  fi
fi

section "Finish"
status_line "Selected" "${selected_label}"
status_line "Written to" "${ENV_FILE}"

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files chatbot.service >/dev/null 2>&1; then
  if confirm "Restart chatbot.service now so the assistant uses the new model immediately" "y"; then
    sudo systemctl restart chatbot.service
    success "chatbot.service restarted."
  else
    note "Restart later with: sudo systemctl restart chatbot.service"
  fi
else
  note "If the assistant is already running, restart it manually to pick up the new model."
fi