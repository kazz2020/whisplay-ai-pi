#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${PROJECT_ROOT}/.env"
LIST_LOCAL_ONLY=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --list-local|--list)
      LIST_LOCAL_ONLY=true
      shift
      ;;
    -h|--help)
      cat <<EOF
Usage: bash switch_litert_model.sh [--list-local] [env-file]

Options:
  --list-local, --list   Print local .litertlm files and exit
  -h, --help             Show this help text
EOF
      exit 0
      ;;
    *)
      ENV_FILE="$1"
      shift
      ;;
  esac
done

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
  printf '%s%s%s\n' "${COLOR_BOLD}${COLOR_CYAN}" "Whisplay LiteRT-LM Model Switcher" "${COLOR_RESET}"
  printf '%s%s%s\n' "${COLOR_DIM}" "Switch the active local LiteRT-LM model in .env without rerunning the full installer." "${COLOR_RESET}"
  hr
}

list_local_models() {
  local target_root="$1"
  local active_model_path="$2"
  local found_any=false
  local normalized_target_root
  local normalized_active_path
  local model_path
  local marker
  local display_path

  normalized_target_root=$(cd "${target_root}" 2>/dev/null && pwd || printf '%s' "${target_root}")
  normalized_active_path=$(cd "$(dirname "${active_model_path}")" 2>/dev/null && pwd && printf '/%s' "$(basename "${active_model_path}")" || printf '%s' "${active_model_path}")

  section "Local LiteRT Models"
  status_line "Scan root" "${normalized_target_root}"
  status_line "Active path" "${active_model_path:-unset}"

  if [ ! -d "${target_root}" ]; then
    warn "LiteRT model directory does not exist yet: ${target_root}"
    return 0
  fi

  while IFS= read -r model_path; do
    found_any=true
    marker=" "
    display_path="$model_path"
    if [ -n "${normalized_target_root}" ]; then
      display_path="${display_path#${normalized_target_root}/}"
    fi
    if [ -n "${normalized_active_path}" ] && [ "${model_path}" = "${normalized_active_path}" ]; then
      marker="*"
    fi
    printf '  %s[%s]%s %s\n' "${COLOR_CYAN}" "${marker}" "${COLOR_RESET}" "${display_path}"
  done < <(find "${target_root}" -type f -name '*.litertlm' | sort)

  if [ "${found_any}" = false ]; then
    note "No local .litertlm files were found under the configured LiteRT model directory."
  else
    note "Entries marked with [*] match the current LITERT_LM_MODEL_PATH."
  fi
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

print_presets() {
  cat <<'EOF'
Low RAM|google/gemma-3n-E2B-it-litert-preview||Gemma 3n E2B Preview|Lowest-RAM experimental preset for Pi 5 8GB
Low RAM|google/gemma-3n-E2B-it-litert-lm||Gemma 3n E2B LiteRT-LM|Fast multilingual default for tight memory budgets
Language Focused|google/gemma-3n-E2B-it-litert-lm||Polish-first Gemma 3n E2B|Use with Polish ASR/TTS when you want the lightest multilingual local model
Language Focused|google/gemma-3n-E2B-it-litert-lm||German-first Gemma 3n E2B|Use with German ASR/TTS when you want the lightest multilingual local model
Balanced|google/gemma-3n-E4B-it-litert-lm||Gemma 3n E4B LiteRT-LM|Stronger multilingual option with moderate RAM needs
Balanced|litert-community/gemma-4-E2B-it-litert-lm||Gemma 4 E2B LiteRT-LM|Best balanced stable local option
Higher Quality|litert-community/gemma-4-E4B-it-litert-lm||Gemma 4 E4B LiteRT-LM|Higher quality, higher RAM usage, better for shorter chat history
EOF
}

download_model_from_hf() {
  local repo_id="$1"
  local target_root="$2"
  local filename_hint="$3"
  local token="$4"
  local download_output

  mkdir -p "${target_root}"
  download_output=$(REPO_ID="${repo_id}" TARGET_ROOT="${target_root}" FILENAME_HINT="${filename_hint}" HF_TOKEN_VALUE="${token}" python3 - <<'PY'
from pathlib import Path
import os

from huggingface_hub import hf_hub_download, list_repo_files

repo_id = os.environ["REPO_ID"]
target_root = Path(os.environ["TARGET_ROOT"]).expanduser()
filename_hint = os.environ.get("FILENAME_HINT", "").strip()
token = os.environ.get("HF_TOKEN_VALUE", "").strip() or None

files = list_repo_files(repo_id=repo_id, repo_type="model", token=token)
candidate = filename_hint if filename_hint and filename_hint in files else ""
if not candidate:
    litert_files = [f for f in files if f.endswith(".litertlm")]
    if not litert_files:
        raise SystemExit(f"No .litertlm file found in {repo_id}")
    candidate = litert_files[0]

download_path = hf_hub_download(
    repo_id=repo_id,
    filename=candidate,
    repo_type="model",
    token=token,
    resume_download=True,
    local_dir=str(target_root),
    local_dir_use_symlinks=False,
)
print(candidate)
print(download_path)
PY
)

  printf '%s\n' "${download_output}"
}

render_menu() {
  local idx
  local current_category=""

  section "Available LiteRT Models"
  note "Pick a preset, use a custom Hugging Face repo, or point to an existing local .litertlm file."
  for idx in "${!repos[@]}"; do
    if [ "${categories[idx]}" != "${current_category}" ]; then
      current_category="${categories[idx]}"
      printf '\n  %s%s%s\n' "${COLOR_BOLD}${COLOR_BLUE}" "${current_category}" "${COLOR_RESET}"
    fi
    printf '  %s%2d)%s %-30s %s\n' "${COLOR_BOLD}${COLOR_CYAN}" "$((idx + 1))" "${COLOR_RESET}" "${labels[idx]}" "${descriptions[idx]}"
  done
  printf '  %s%2d)%s %s\n' "${COLOR_BOLD}${COLOR_CYAN}" "$(( ${#repos[@]} + 1 ))" "${COLOR_RESET}" "Custom Hugging Face LiteRT repo"
  printf '  %s%2d)%s %s\n' "${COLOR_BOLD}${COLOR_CYAN}" "$(( ${#repos[@]} + 2 ))" "${COLOR_RESET}" "Existing local .litertlm file"
}

if [ ! -f "${ENV_FILE}" ]; then
  die "Missing env file: ${ENV_FILE}"
fi

if [ ! -s "${ENV_FILE}" ]; then
  die "Env file is empty: ${ENV_FILE}"
fi

print_banner

current_llm_server=$(get_env_value "LLM_SERVER" || true)
current_model_repo=$(get_env_value "LITERT_LM_MODEL_REPO" || true)
current_model_path=$(get_env_value "LITERT_LM_MODEL_PATH" || true)
current_backend=$(get_env_value "LITERT_LM_BACKEND" || true)
current_cache_dir=$(get_env_value "LITERT_LM_CACHE_DIR" || true)
hf_token=$(get_env_value "HF_TOKEN" || true)
target_root=$(get_env_value "LITERT_LM_MODEL_DIR" || true)

if [ -z "${target_root}" ]; then
  target_root="${HOME}/litert-lm-models"
fi

if [ "${LIST_LOCAL_ONLY}" = true ]; then
  list_local_models "${target_root}" "${current_model_path}"
  exit 0
fi

section "Current Configuration"
status_line "Env file" "${ENV_FILE}"
status_line "LLM server" "${current_llm_server:-unset}"
status_line "Model repo" "${current_model_repo:-unset}"
status_line "Model path" "${current_model_path:-unset}"
status_line "Backend" "${current_backend:-cpu}"

if [ "${current_llm_server}" != "litert-lm" ]; then
  warn "Current LLM provider is not LiteRT-LM."
  if ! confirm "Switch LLM_SERVER to litert-lm and continue" "y"; then
    die "Aborted before changing provider."
  fi
  set_env_value "LLM_SERVER" "litert-lm"
  current_llm_server="litert-lm"
  success "LLM_SERVER updated to litert-lm."
fi

declare -a repos=()
declare -a filenames=()
declare -a categories=()
declare -a labels=()
declare -a descriptions=()

while IFS='|' read -r category repo filename label description; do
  [ -n "${repo}" ] || continue
  categories+=("${category}")
  repos+=("${repo}")
  filenames+=("${filename}")
  labels+=("${label}")
  descriptions+=("${description}")
done < <(print_presets)

if [ -n "${current_model_repo}" ]; then
  found_current=false
  for repo in "${repos[@]}"; do
    if [ "${repo}" = "${current_model_repo}" ]; then
      found_current=true
      break
    fi
  done
  if [ "${found_current}" = false ]; then
    categories=("Current" "${categories[@]}")
    repos=("${current_model_repo}" "${repos[@]}")
    filenames=("" "${filenames[@]}")
    labels=("${current_model_repo} (current repo)" "${labels[@]}")
    descriptions=("Currently configured LiteRT repo" "${descriptions[@]}")
  fi
fi

render_menu
custom_repo_option=$(( ${#repos[@]} + 1 ))
local_file_option=$(( ${#repos[@]} + 2 ))
choice=$(choose_option "${local_file_option}")

selected_repo=""
selected_filename=""
selected_model_path=""
selected_label=""

if [ "${choice}" -eq "${custom_repo_option}" ]; then
  selected_repo=$(prompt="Enter LiteRT-LM Hugging Face repo"; read -r -p "${prompt}: " reply; printf '%s' "$(trim_value "${reply}")")
  [ -n "${selected_repo}" ] || die "Repository cannot be empty."
  read -r -p "Optional exact .litertlm filename (leave blank for auto-detect): " selected_filename
  selected_filename=$(trim_value "${selected_filename}")
  selected_label="${selected_repo}"
elif [ "${choice}" -eq "${local_file_option}" ]; then
  read -r -p "Enter the full path to the local .litertlm file: " selected_model_path
  selected_model_path=$(trim_value "${selected_model_path}")
  [ -n "${selected_model_path}" ] || die "Model path cannot be empty."
  selected_label="${selected_model_path}"
else
  selected_repo="${repos[$((choice - 1))]}"
  selected_filename="${filenames[$((choice - 1))]}"
  selected_label="${labels[$((choice - 1))]}"
fi

current_backend=${current_backend:-cpu}
current_cache_dir=${current_cache_dir:-${HOME}/.cache/litert-lm}

section "Options"
read -r -p "LiteRT-LM backend [${current_backend}]: " backend_reply
selected_backend=$(trim_value "${backend_reply:-${current_backend}}")
read -r -p "LiteRT-LM cache dir [${current_cache_dir}]: " cache_reply
selected_cache_dir=$(trim_value "${cache_reply:-${current_cache_dir}}")

if [ -n "${selected_repo}" ]; then
  if confirm "Download the selected LiteRT model from Hugging Face now" "y"; then
    section "Downloading"
    info "Downloading from ${selected_repo}"
    download_output=$(download_model_from_hf "${selected_repo}" "${target_root}" "${selected_filename}" "${hf_token}")
    selected_filename=$(printf '%s\n' "${download_output}" | tail -n 2 | head -n 1)
    selected_model_path=$(printf '%s\n' "${download_output}" | tail -n 1)
    [ -f "${selected_model_path}" ] || die "Downloaded LiteRT model path is invalid."
    success "Model downloaded to ${selected_model_path}"
  else
    read -r -p "Enter the full path to the existing local .litertlm file: " selected_model_path
    selected_model_path=$(trim_value "${selected_model_path}")
    [ -n "${selected_model_path}" ] || die "Model path cannot be empty."
  fi
fi

section "Review Change"
status_line "Current repo" "${current_model_repo:-unset}"
status_line "Current path" "${current_model_path:-unset}"
status_line "New selection" "${selected_label}"
status_line "New path" "${selected_model_path}"

if ! confirm "Apply this LiteRT-LM model change" "y"; then
  die "No changes were written."
fi

set_env_value "LLM_SERVER" "litert-lm"
set_env_value "LITERT_LM_BACKEND" "${selected_backend}"
set_env_value "LITERT_LM_CACHE_DIR" "${selected_cache_dir}"
set_env_value "LITERT_LM_MODEL_PATH" "${selected_model_path}"
if [ -n "${selected_repo}" ]; then
  set_env_value "LITERT_LM_MODEL_REPO" "${selected_repo}"
else
  set_env_value "LITERT_LM_MODEL_REPO" "local-file"
fi

success "Updated LiteRT-LM model settings in ${ENV_FILE}."

section "Finish"
status_line "Model path" "${selected_model_path}"
status_line "Backend" "${selected_backend}"

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files chatbot.service >/dev/null 2>&1; then
  if confirm "Restart chatbot.service now so the assistant uses the new LiteRT model immediately" "y"; then
    sudo systemctl restart chatbot.service
    success "chatbot.service restarted."
  else
    note "Restart later with: sudo systemctl restart chatbot.service"
  fi
else
  note "If the assistant is already running, restart it manually to pick up the new model."
fi