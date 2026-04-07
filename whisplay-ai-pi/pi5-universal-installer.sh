#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT="${SCRIPT_DIR}"
PREFERRED_DRIVER_DIR="${PROJECT_ROOT}/../Whisplay-main"
PREFERRED_LLAMA_DIR="${PROJECT_ROOT}/../llama.cpp-master"
DRIVER_REPO_URL="https://github.com/PiSugar/whisplay.git"
LLAMA_REPO_URL="https://github.com/ggml-org/llama.cpp.git"
DEFAULT_PIPER_DIR="${HOME}/piper"
DRIVER_REBOOT_RECOMMENDED=false
ASR_LANGUAGE="en"
ASSISTANT_SYSTEM_PROMPT="You are a practical voice assistant running on a Raspberry Pi. Reply in English unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess."
LLM_SERVER_SELECTION="llama.cpp"
LLM_PROVIDER="llama.cpp"
SERVE_LLAMA_CPP_VALUE="true"
SERVE_OLLAMA_VALUE="false"
OLLAMA_ENDPOINT_VALUE="http://192.168.1.100:11434"
OLLAMA_MODEL_VALUE="gemma3:4b"
OLLAMA_ENABLE_TOOLS_VALUE="false"
OPENAI_API_BASE_URL_VALUE="https://api.deepseek.com/v1"
OPENAI_API_KEY_VALUE=""
OPENAI_LLM_MODEL_VALUE="deepseek-chat"
OPENAI_ENABLE_TOOLS_VALUE="false"
LLAMA_CPP_HF_TOKEN_VALUE="${HF_TOKEN:-}"
WAKE_WORD_ENGINE="disabled"
WAKE_WORD_PHRASE=""
WAKE_WORD_REFERENCE_DIR=""
WAKE_WORD_THRESHOLD="0.16"
WAKE_WORD_BUFFER_SIZE="1.8"
WAKE_WORD_SLIDE_SIZE="0.25"
WAKE_WORD_SAMPLE_COUNT="4"
WAKE_WORD_SAMPLE_DURATION="3"
WAKE_WORD_OPENWAKEWORD_MODEL="hey_jarvis"
RECORD_WAKE_WORD_SAMPLES=false

if [ -t 1 ]; then
  COLOR_RESET=$(printf '\033[0m')
  COLOR_BOLD=$(printf '\033[1m')
  COLOR_DIM=$(printf '\033[2m')
  COLOR_BLUE=$(printf '\033[34m')
  COLOR_CYAN=$(printf '\033[36m')
  COLOR_GREEN=$(printf '\033[32m')
  COLOR_YELLOW=$(printf '\033[33m')
else
  COLOR_RESET=""
  COLOR_BOLD=""
  COLOR_DIM=""
  COLOR_BLUE=""
  COLOR_CYAN=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
fi

log() {
  echo "[pi5-installer] $*"
}

warn() {
  echo "[pi5-installer] $*" >&2
}

die() {
  echo "[pi5-installer] $*" >&2
  exit 1
}

print_divider() {
  printf '\n%s%s%s\n' "${COLOR_DIM}" "------------------------------------------------------------" "${COLOR_RESET}"
}

print_section() {
  local title="$1"
  print_divider
  printf '%s%s%s\n' "${COLOR_BOLD}${COLOR_CYAN}" "${title}" "${COLOR_RESET}"
}

print_note() {
  local text="$1"
  printf '%s%s%s\n' "${COLOR_DIM}" "${text}" "${COLOR_RESET}"
}

print_review_item() {
  local label="$1"
  local value="$2"
  printf '  %s%-28s%s %s\n' "${COLOR_GREEN}" "${label}" "${COLOR_RESET}" "${value}"
}

format_enabled() {
  if [ "$1" = true ]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

mask_secret() {
  local value="$1"
  local length=${#value}

  if [ -z "${value}" ]; then
    printf '(not set)'
  elif [ "${length}" -le 8 ]; then
    printf '********'
  else
    printf '%s***%s' "${value:0:4}" "${value:length-4:4}"
  fi
}

print_final_review() {
  print_section "Final review"
  print_note "Check the plan below. Nothing has been installed yet."

  print_review_item "Install driver" "$(format_enabled "${INSTALL_DRIVER}")"
  print_review_item "Install dependencies" "$(format_enabled "${INSTALL_CHATBOT_DEPS}")"
  print_review_item "Install local ASR" "$(format_enabled "${INSTALL_LOCAL_ASR}")"
  print_review_item "Install local TTS" "$(format_enabled "${INSTALL_LOCAL_TTS}")"
  print_review_item "Build chatbot app" "$(format_enabled "${BUILD_CHATBOT}")"
  print_review_item "Install systemd service" "$(format_enabled "${INSTALL_SERVICE}")"
  print_review_item "Install wake word" "$(format_enabled "${INSTALL_WAKE_WORD}")"

  if [ "${LLM_SERVER_SELECTION}" = "llama.cpp" ]; then
    print_review_item "LLM runtime" "local llama.cpp"
    print_review_item "Brain profile" "${BRAIN_PROFILE_LABEL}"
    print_review_item "Model repo" "${LLAMA_HF_REPO}"
    print_review_item "Model alias" "${LLAMA_ALIAS}"
    print_review_item "Install llama.cpp" "$(format_enabled "${INSTALL_LLAMA_CPP}")"
    print_review_item "Pre-download LLM" "$(format_enabled "${DOWNLOAD_LLM_MODEL}")"
    print_review_item "HF token" "$(mask_secret "${LLAMA_CPP_HF_TOKEN_VALUE:-}")"
    print_review_item "llama.cpp repo dir" "${LLAMA_DIR}"
    print_review_item "Threads / ctx" "${CHATBOT_THREADS} / ${CHATBOT_CONTEXT}"
    print_review_item "Batch / ubatch" "${CHATBOT_BATCH} / ${CHATBOT_UBATCH}"
  elif [ "${LLM_SERVER_SELECTION}" = "ollama" ]; then
    print_review_item "LLM runtime" "LAN Ollama"
    print_review_item "Profile" "${BRAIN_PROFILE_LABEL}"
    print_review_item "Ollama endpoint" "${OLLAMA_ENDPOINT_VALUE}"
    print_review_item "Ollama model" "${OLLAMA_MODEL_VALUE}"
  elif [ "${LLM_SERVER_SELECTION}" = "ollama-cloud" ]; then
    print_review_item "LLM runtime" "Ollama Cloud"
    print_review_item "Profile" "${BRAIN_PROFILE_LABEL}"
    print_review_item "Cloud endpoint" "${OLLAMA_ENDPOINT_VALUE}"
    print_review_item "Cloud model" "${OLLAMA_MODEL_VALUE}"
    print_review_item "OLLAMA_API_KEY" "$(mask_secret "${OLLAMA_API_KEY_VALUE}")"
  else
    print_review_item "LLM runtime" "OpenAI-compatible API"
    print_review_item "Profile" "${BRAIN_PROFILE_LABEL}"
    print_review_item "API base URL" "${OPENAI_API_BASE_URL_VALUE}"
    print_review_item "Model" "${OPENAI_LLM_MODEL_VALUE}"
    print_review_item "API key" "$(mask_secret "${OPENAI_API_KEY_VALUE}")"
  fi

  print_review_item "ASR model" "${ASR_MODEL}"
  print_review_item "ASR language" "${ASR_LANGUAGE}"
  print_review_item "Piper voice" "${PIPER_VOICE}"
  print_review_item "Piper dir" "${PIPER_DIR}"
  print_review_item "Chat history limit" "${CHATBOT_MAX_MESSAGES}"
  print_review_item "Driver repo dir" "${DRIVER_DIR}"
  print_review_item "Env template" "${CHATBOT_ENV_TEMPLATE}"
  print_review_item "Env output" "${CHATBOT_ENV_FILE}"

  if [ "${INSTALL_WAKE_WORD}" = true ]; then
    print_review_item "Wake engine" "${WAKE_WORD_ENGINE}"
    if [ "${WAKE_WORD_ENGINE}" = "local-wake" ]; then
      print_review_item "Wake phrase" "${WAKE_WORD_PHRASE}"
      print_review_item "Wake sample dir" "${WAKE_WORD_REFERENCE_DIR}"
      print_review_item "Record samples" "$(format_enabled "${RECORD_WAKE_WORD_SAMPLES}")"
    else
      print_review_item "Wake model" "${WAKE_WORD_OPENWAKEWORD_MODEL}"
    fi
  fi
}

reset_install_choices() {
  ASR_LANGUAGE="en"
  ASSISTANT_SYSTEM_PROMPT="You are a practical voice assistant running on a Raspberry Pi. Reply in English unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess."
  LLM_SERVER_SELECTION="llama.cpp"
  LLM_PROVIDER="llama.cpp"
  SERVE_LLAMA_CPP_VALUE="true"
  SERVE_OLLAMA_VALUE="false"
  OLLAMA_ENDPOINT_VALUE="http://192.168.1.100:11434"
  OLLAMA_MODEL_VALUE="gemma3:4b"
  OLLAMA_ENABLE_TOOLS_VALUE="false"
  OLLAMA_API_KEY_VALUE=""
  OPENAI_API_BASE_URL_VALUE="https://api.deepseek.com/v1"
  OPENAI_API_KEY_VALUE=""
  OPENAI_LLM_MODEL_VALUE="deepseek-chat"
  OPENAI_ENABLE_TOOLS_VALUE="false"
  LLAMA_CPP_HF_TOKEN_VALUE="${HF_TOKEN:-}"
  WAKE_WORD_ENGINE="disabled"
  WAKE_WORD_PHRASE=""
  WAKE_WORD_REFERENCE_DIR=""
  WAKE_WORD_THRESHOLD="0.16"
  WAKE_WORD_BUFFER_SIZE="1.8"
  WAKE_WORD_SLIDE_SIZE="0.25"
  WAKE_WORD_SAMPLE_COUNT="4"
  WAKE_WORD_SAMPLE_DURATION="3"
  WAKE_WORD_OPENWAKEWORD_MODEL="hey_jarvis"
  RECORD_WAKE_WORD_SAMPLES=false
  INSTALL_DRIVER=false
  INSTALL_CHATBOT_DEPS=false
  INSTALL_LLAMA_CPP=false
  INSTALL_LOCAL_ASR=false
  INSTALL_LOCAL_TTS=false
  BUILD_CHATBOT=false
  INSTALL_SERVICE=false
  DOWNLOAD_LLM_MODEL=false
  DOWNLOAD_ASR_MODEL=false
  INSTALL_WAKE_WORD=false
  BRAIN_PROFILE_NAME="balanced"
  BRAIN_PROFILE_LABEL="Balanced"
  BRAIN_THREADS_DEFAULT="4"
  BRAIN_CONTEXT_DEFAULT="2048"
  BRAIN_BATCH_DEFAULT="256"
  BRAIN_UBATCH_DEFAULT="128"
  BRAIN_MAX_MESSAGES_DEFAULT="12"
  LLAMA_HF_REPO="bartowski/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M"
  LLAMA_ALIAS="qwen2.5-1.5b-instruct"
  ASR_MODEL="tiny"
  PIPER_VOICE="en_US-lessac-medium"
  CHATBOT_ENV_TEMPLATE="${PROJECT_ROOT}/.env.pi5-local.template"
  CHATBOT_ENV_FILE="${PROJECT_ROOT}/.env"
  DRIVER_DIR="${PREFERRED_DRIVER_DIR}"
  LLAMA_DIR="${PREFERRED_LLAMA_DIR}"
  PIPER_DIR="${DEFAULT_PIPER_DIR}"
  CHATBOT_THREADS="${BRAIN_THREADS_DEFAULT}"
  CHATBOT_CONTEXT="${BRAIN_CONTEXT_DEFAULT}"
  CHATBOT_BATCH="${BRAIN_BATCH_DEFAULT}"
  CHATBOT_UBATCH="${BRAIN_UBATCH_DEFAULT}"
  CHATBOT_MAX_MESSAGES="${BRAIN_MAX_MESSAGES_DEFAULT}"
}

print_intro() {
  print_divider
  printf '%s%s%s\n' "${COLOR_BOLD}${COLOR_BLUE}" "Whisplay Pi 5 Installer" "${COLOR_RESET}"
  print_note "Interactive setup for the device stack, assistant runtime, and optional wake word support."
}

choose_from_menu() {
  local title="$1"
  local default_value="$2"
  shift 2

  print_section "${title}"
  local entry key label choices=""
  for entry in "$@"; do
    key="${entry%%|*}"
    label="${entry#*|}"
    printf '  %s[%s]%s %s\n' "${COLOR_GREEN}" "${key}" "${COLOR_RESET}" "${label}"
    if [ -n "${choices}" ]; then
      choices="${choices}, ${key}"
    else
      choices="${key}"
    fi
  done

  local reply
  while true; do
    read -r -p "${COLOR_BOLD}Select an option${COLOR_RESET} [${default_value}]: " reply
    reply="${reply:-$default_value}"
    for entry in "$@"; do
      key="${entry%%|*}"
      if [ "${reply}" = "${key}" ]; then
        printf '%s\n' "${reply}"
        return 0
      fi
    done
    warn "Please enter one of: ${choices}"
  done
}

prompt_yes_no() {
  local prompt="$1"
  local default_value="$2"
  local reply
  local hint

  if [ "${default_value}" = "y" ] || [ "${default_value}" = "Y" ]; then
    hint="Y/n"
  else
    hint="y/N"
  fi

  while true; do
    read -r -p "${COLOR_BOLD}${prompt}${COLOR_RESET} ${COLOR_DIM}[${hint}]${COLOR_RESET} " reply
    reply="${reply:-$default_value}"
    case "${reply}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
    esac
    warn "Please answer y or n."
  done
}

prompt_value() {
  local prompt="$1"
  local default_value="$2"
  local reply
  read -r -p "${COLOR_BOLD}${prompt}${COLOR_RESET} ${COLOR_DIM}[${default_value}]${COLOR_RESET} " reply
  printf '%s\n' "${reply:-$default_value}"
}

prompt_required_value() {
  local prompt="$1"
  local reply
  while true; do
    read -r -p "${COLOR_BOLD}${prompt}${COLOR_RESET}: " reply
    if [ -n "${reply}" ]; then
      printf '%s\n' "${reply}"
      return 0
    fi

    warn "A value is required for this option."
  done
}

pick_llama_hf_auth() {
  if [ "${LLM_SERVER_SELECTION}" != "llama.cpp" ] || [ -z "${LLAMA_HF_REPO:-}" ]; then
    return 0
  fi

  if prompt_yes_no "Use a Hugging Face token for llama.cpp model access/download" "n"; then
    LLAMA_CPP_HF_TOKEN_VALUE=$(prompt_required_value "Enter Hugging Face token (hf_...)")
  fi
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

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


set_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local escaped_value

  escaped_value=$(printf '%s' "${value}" | sed 's/\\/\\\\/g; s/"/\\"/g')
  if grep -Eq "^[# ]*${key}=" "${file}"; then
    sed -i "s|^[# ]*${key}=.*|${key}=\"${escaped_value}\"|" "${file}"
  else
    printf '%s="%s"\n' "${key}" "${escaped_value}" >> "${file}"
  fi
}

ensure_repo() {
  local repo_dir="$1"
  local repo_url="$2"
  local repo_name="$3"
  if [ -d "${repo_dir}" ]; then
    log "Using existing ${repo_name} repo at ${repo_dir}"
    return 0
  fi
  mkdir -p "$(dirname "${repo_dir}")"
  log "Cloning ${repo_name} into ${repo_dir}"
  git clone --depth 1 "${repo_url}" "${repo_dir}"
}

patch_whisplay_driver_installer() {
  local repo_dir="$1"
  local installer_path="${repo_dir}/Driver/install_wm8960_drive.sh"

  if [ ! -f "${installer_path}" ]; then
    log "Whisplay driver installer not found at ${installer_path}; skipping local compatibility patch"
    return 0
  fi

  if grep -Fq 'return 0 # keep power warnings non-fatal for callers' "${installer_path}"; then
    return 0
  fi

  if grep -Fq '[[ "$warned" -eq 0 ]] && ok "No obvious power warnings detected since boot."' "${installer_path}"; then
    INSTALLER_PATH="${installer_path}" python3 - <<'PY'
from pathlib import Path
import os

path = Path(os.environ["INSTALLER_PATH"])
text = path.read_text()
old = '  [[ "$warned" -eq 0 ]] && ok "No obvious power warnings detected since boot."\n}\n'
new = '  if [[ "$warned" -eq 0 ]]; then\n    ok "No obvious power warnings detected since boot."\n  fi\n\n  return 0 # keep power warnings non-fatal for callers\n}\n'

if old not in text:
    raise SystemExit("Expected power_warning block not found")

path.write_text(text.replace(old, new, 1))
PY
    log "Patched upstream Whisplay driver installer to keep power warnings non-fatal"
  fi
}

find_llama_server_bin() {
  local candidates=(
    "/usr/local/bin/llama-server"
    "${LLAMA_DIR}/build/bin/llama-server"
    "${PROJECT_ROOT}/../llama.cpp-master/build/bin/llama-server"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -x "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

download_faster_whisper_model() {
  if [ -d "${ASR_MODEL}" ]; then
    log "faster-whisper model path already points to a local directory: ${ASR_MODEL}"
    return 0
  fi

  log "Pre-downloading faster-whisper model: ${ASR_MODEL}"
  ASR_MODEL_NAME="${ASR_MODEL}" HF_TOKEN_VALUE="${LLAMA_CPP_HF_TOKEN_VALUE:-${HF_TOKEN:-}}" python3 - <<'PY'
import os
import subprocess
import sys

model_name = os.environ["ASR_MODEL_NAME"].strip()
token = os.environ.get("HF_TOKEN_VALUE", "").strip() or None

repo_map = {
    "tiny": "Systran/faster-whisper-tiny",
    "tiny.en": "Systran/faster-whisper-tiny.en",
    "base": "Systran/faster-whisper-base",
    "base.en": "Systran/faster-whisper-base.en",
    "small": "Systran/faster-whisper-small",
    "small.en": "Systran/faster-whisper-small.en",
    "medium": "Systran/faster-whisper-medium",
    "medium.en": "Systran/faster-whisper-medium.en",
    "large-v1": "Systran/faster-whisper-large-v1",
    "large-v2": "Systran/faster-whisper-large-v2",
    "large-v3": "Systran/faster-whisper-large-v3",
    "large": "Systran/faster-whisper-large-v3",
    "distil-small.en": "Systran/faster-distil-whisper-small.en",
    "distil-medium.en": "Systran/faster-distil-whisper-medium.en",
    "distil-large-v2": "Systran/faster-distil-whisper-large-v2",
    "distil-large-v3": "Systran/faster-distil-whisper-large-v3",
}

repo_id = repo_map.get(model_name, model_name)

try:
    from huggingface_hub import hf_hub_download, list_repo_files
except Exception:
    subprocess.check_call([
        sys.executable,
        "-m",
        "pip",
        "install",
        "--break-system-packages",
        "huggingface_hub>=0.30.0",
    ])
    from huggingface_hub import hf_hub_download, list_repo_files

print(f"Downloading faster-whisper files from: {repo_id}", flush=True)
if token:
    print("Using Hugging Face token for faster-whisper download", flush=True)

all_files = list_repo_files(repo_id=repo_id, repo_type="model", token=token)
skip_suffixes = (".md", ".txt")
skip_names = {".gitattributes", "README.md"}
files = [
    name for name in all_files
    if name not in skip_names and not name.lower().endswith(skip_suffixes)
]

if not files:
  raise SystemExit(f"No downloadable model files found in repo: {repo_id}")

files.sort()
local_path = ""
for index, filename in enumerate(files, start=1):
  print(f"[{index}/{len(files)}] Downloading {filename}", flush=True)
  local_path = hf_hub_download(
    repo_id=repo_id,
    filename=filename,
    repo_type="model",
    token=token,
  )

local_path = os.path.dirname(local_path)
print(f"faster-whisper model ready: {local_path}", flush=True)
PY
}

install_local_wake_runtime() {
  log "Installing local-wake dependencies"
  sudo apt-get update
  sudo apt-get install -y libportaudio2 sox libsox-fmt-mp3
  python3 -m pip install --break-system-packages local-wake==0.1.2
}

install_openwakeword_runtime() {
  log "Installing openWakeWord dependencies"
  sudo apt-get update
  sudo apt-get install -y sox libsox-fmt-mp3
  python3 -m pip install --break-system-packages openwakeword==0.6.0
}

record_local_wake_samples() {
  local sample_dir="$1"
  local sample_count="$2"
  local sample_duration="$3"
  local phrase="$4"

  sample_count=$(normalize_positive_int "${sample_count}" "4")
  sample_duration=$(normalize_positive_int "${sample_duration}" "3")

  mkdir -p "${sample_dir}"

  if compgen -G "${sample_dir}/*.wav" >/dev/null 2>&1; then
    if prompt_yes_no "Existing wake word samples found in ${sample_dir}. Replace them" "y"; then
      rm -f "${sample_dir}"/*.wav
    fi
  fi

  WAKE_WORD_REFERENCE_DIR="${sample_dir}" \
  WAKE_WORD_PHRASE="${phrase}" \
  WAKE_WORD_LOCAL_WAKE_BIN="${WAKE_WORD_LOCAL_WAKE_BIN:-lwake}" \
  bash "${PROJECT_ROOT}/scripts/setup_local_wakeword.sh" \
    "${sample_count}" "${sample_duration}"
}

download_llama_cpp_model() {
  if [ -n "${LLAMA_HF_REPO:-}" ]; then
    log "Pre-downloading llama.cpp model from Hugging Face: ${LLAMA_HF_REPO}"
    if download_llama_cpp_model_via_hf; then
      return 0
    fi
    warn "Direct Hugging Face pre-download failed; falling back to llama-server warm-up"
  fi

  local server_bin
  server_bin=$(find_llama_server_bin) || {
    warn "llama-server binary not found after install; skipping llama.cpp model warm-up"
    return 1
  }

  if [ -n "${LLAMA_CPP_MODEL_PATH:-}" ] && [ -f "${LLAMA_CPP_MODEL_PATH}" ]; then
    log "Using existing local GGUF model: ${LLAMA_CPP_MODEL_PATH}"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log "Installing curl for llama.cpp model warm-up"
    sudo apt-get update
    sudo apt-get install -y curl
  fi

  log "Pre-downloading llama.cpp model via llama-server: ${LLAMA_HF_REPO}"
  local llama_host llama_port llama_pid ready=0
  local last_progress_line=""
  local loop_count=0
  local saw_main_loop=0
  local saw_download_progress=0
  local start_ts
  local health_url models_url log_file
  llama_host="127.0.0.1"
  llama_port="18080"
  health_url="http://${llama_host}:${llama_port}/health"
  models_url="http://${llama_host}:${llama_port}/v1/models"
  log_file="/tmp/whisplay-llama-download.log"
  start_ts=$(date +%s)

  : > "${log_file}"

  (
    LLAMA_CPP_SERVER_BIN="${server_bin}" \
    LLAMA_CPP_HOST="${llama_host}" \
    LLAMA_CPP_PORT="${llama_port}" \
    LLAMA_CPP_HF_REPO="${LLAMA_HF_REPO}" \
    LLAMA_CPP_ALIAS="${LLAMA_ALIAS}" \
    LLAMA_CPP_MODEL="${LLAMA_ALIAS}" \
    LLAMA_CPP_THREADS="${CHATBOT_THREADS}" \
    LLAMA_CPP_CONTEXT_SIZE="${CHATBOT_CONTEXT}" \
    LLAMA_CPP_BATCH_SIZE="${CHATBOT_BATCH}" \
    LLAMA_CPP_UBATCH_SIZE="${CHATBOT_UBATCH}" \
    LLAMA_CPP_ENABLE_TOOLS="false" \
    LLAMA_CPP_EXTRA_ARGS="--parallel 1" \
    bash "${PROJECT_ROOT}/scripts/serve_llama_cpp.sh"
  ) >"${log_file}" 2>&1 &
  llama_pid=$!

  for _ in $(seq 1 900); do
    loop_count=$((loop_count + 1))

    if ! kill -0 "${llama_pid}" >/dev/null 2>&1; then
      warn "llama-server exited before becoming ready"
      tail -n 200 "${log_file}" >&2 || true
      return 1
    fi

    if [ -s "${log_file}" ]; then
      local progress_line
      progress_line=$(python3 - <<PY
from pathlib import Path

path = Path(${log_file@Q})
data = path.read_bytes()[-8192:]
text = data.decode("utf-8", errors="ignore").replace("\r", "\n")
matches = []
for line in text.splitlines():
    lower = line.lower()
    if any(token in lower for token in ["download", "progress", "gguf", "transferred", "bytes", "%", "eta", "model", "listening", "loading", "main:"]):
        matches.append(line.strip())
if matches:
    print(matches[-1])
PY
)
      if [ -n "${progress_line}" ] && [ "${progress_line}" != "${last_progress_line}" ]; then
        log "llama.cpp: ${progress_line}"
        last_progress_line="${progress_line}"
        case "${progress_line}" in
          *"%"*|*"download"*|*"transferred"*|*"bytes"*|*"eta"*)
            saw_download_progress=1
            ;;
          *"main: starting the main loop"*)
            saw_main_loop=1
            ;;
        esac
      elif [ $((loop_count % 10)) -eq 0 ]; then
        local log_size elapsed_seconds
        log_size=$(wc -c < "${log_file}" 2>/dev/null || echo 0)
        elapsed_seconds=$(( $(date +%s) - start_ts ))
        log "llama.cpp warm-up still running after ${elapsed_seconds}s. Log size: ${log_size} bytes. Current log: ${log_file}"
      fi
    elif [ $((loop_count % 10)) -eq 0 ]; then
      local elapsed_seconds
      elapsed_seconds=$(( $(date +%s) - start_ts ))
      log "Waiting for llama-server to start and begin downloading... (${elapsed_seconds}s elapsed)"
    fi

    if curl --connect-timeout 2 --max-time 4 -sf "${health_url}" >/dev/null 2>&1 || \
       curl --connect-timeout 2 --max-time 4 -sf "${models_url}" >/dev/null 2>&1; then
      ready=1
      break
    fi

    if [ "${saw_main_loop}" -eq 1 ]; then
      ready=1
      break
    fi

    sleep 2
  done

  if [ "${ready}" -ne 1 ]; then
    kill "${llama_pid}" >/dev/null 2>&1 || true
    wait "${llama_pid}" 2>/dev/null || true
    warn "llama-server did not become ready in time"
    tail -n 200 "${log_file}" >&2 || true
    return 1
  fi

  curl -sf "http://${llama_host}:${llama_port}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${LLAMA_ALIAS}\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}],\"stream\":false,\"max_tokens\":1}" \
    >/tmp/whisplay-llama-download-request.json

  if [ "${saw_download_progress}" -ne 1 ]; then
    log "llama.cpp did not emit visible download percentages. This usually means the model was already cached or llama.cpp downloaded it without line-by-line progress output."
  fi

  kill "${llama_pid}" >/dev/null 2>&1 || true
  wait "${llama_pid}" 2>/dev/null || true
  log "llama.cpp model ready"
}

download_llama_cpp_model_via_hf() {
  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found; cannot use direct Hugging Face pre-download"
    return 1
  fi

  log "Trying direct Hugging Face download for faster, visible GGUF progress"
  local download_output download_path
  download_output=$(REPO_SPEC="${LLAMA_HF_REPO}" HF_TOKEN_VALUE="${LLAMA_CPP_HF_TOKEN_VALUE:-}" python3 - <<'PY'
import os
import subprocess
import sys

repo_spec = os.environ["REPO_SPEC"].strip()
token = os.environ.get("HF_TOKEN_VALUE", "").strip() or None

try:
    from huggingface_hub import hf_hub_download, list_repo_files
except Exception:
    subprocess.check_call([
        sys.executable,
        "-m",
        "pip",
        "install",
        "--break-system-packages",
        "huggingface_hub>=0.30.0",
    ])
    from huggingface_hub import hf_hub_download, list_repo_files

if ":" in repo_spec:
    repo_id, selector = repo_spec.rsplit(":", 1)
else:
    repo_id, selector = repo_spec, ""

selector_lower = selector.lower()
files = list_repo_files(repo_id=repo_id, repo_type="model", token=token)
ggufs = [name for name in files if name.lower().endswith(".gguf")]
if not ggufs:
    raise SystemExit(f"No GGUF files found in Hugging Face repo: {repo_id}")

if selector:
    exact = [name for name in ggufs if name == selector or os.path.basename(name) == selector]
    if exact:
        target = exact[0]
    else:
        contains = [name for name in ggufs if selector_lower in os.path.basename(name).lower()]
        if not contains:
            raise SystemExit(f"Could not find a GGUF file matching '{selector}' in repo {repo_id}")
        contains.sort(key=lambda item: (len(os.path.basename(item)), item))
        target = contains[0]
else:
    ggufs.sort(key=lambda item: (len(os.path.basename(item)), item))
    target = ggufs[0]

print(f"Resolved GGUF file: {target}", file=sys.stderr)
local_path = hf_hub_download(
    repo_id=repo_id,
    filename=target,
    repo_type="model",
    token=token,
    resume_download=True,
)
print(local_path)
PY
)
  download_path=$(printf '%s\n' "${download_output}" | tail -n 1)

  if [ -z "${download_path}" ] || [ ! -f "${download_path}" ]; then
    warn "Hugging Face pre-download did not return a valid model path"
    return 1
  fi

  export LLAMA_CPP_MODEL_PATH="${download_path}"
  if [ -n "${CHATBOT_ENV_FILE:-}" ] && [ -f "${CHATBOT_ENV_FILE}" ]; then
    set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_MODEL_PATH" "${download_path}"
  fi
  log "llama.cpp GGUF ready at: ${download_path}"
  return 0
}

pick_llm_repo() {
  local choice
  choice=$(choose_from_menu \
    "Select the assistant brain profile" \
    "2" \
    "1|Fast: Qwen2.5 0.5B Instruct Q4_K_M" \
    "2|Balanced: Qwen2.5 1.5B Instruct Q4_K_M (recommended)" \
    "3|Higher quality: Gemma 2 2B Instruct Q4_K_M" \
    "4|Custom Hugging Face GGUF repo")
  case "${choice}" in
    1)
      LLM_PROVIDER="llama.cpp"
      BRAIN_PROFILE_NAME="fast"
      BRAIN_PROFILE_LABEL="Fast"
      LLAMA_HF_REPO="bartowski/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M"
      LLAMA_ALIAS="qwen2.5-0.5b-instruct"
      BRAIN_THREADS_DEFAULT="4"
      BRAIN_CONTEXT_DEFAULT="1536"
      BRAIN_BATCH_DEFAULT="192"
      BRAIN_UBATCH_DEFAULT="96"
      BRAIN_MAX_MESSAGES_DEFAULT="10"
      ;;
    2)
      LLM_PROVIDER="llama.cpp"
      BRAIN_PROFILE_NAME="balanced"
      BRAIN_PROFILE_LABEL="Balanced"
      LLAMA_HF_REPO="bartowski/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M"
      LLAMA_ALIAS="qwen2.5-1.5b-instruct"
      BRAIN_THREADS_DEFAULT="4"
      BRAIN_CONTEXT_DEFAULT="2048"
      BRAIN_BATCH_DEFAULT="256"
      BRAIN_UBATCH_DEFAULT="128"
      BRAIN_MAX_MESSAGES_DEFAULT="12"
      ;;
    3)
      LLM_PROVIDER="llama.cpp"
      BRAIN_PROFILE_NAME="quality"
      BRAIN_PROFILE_LABEL="Higher quality"
      LLAMA_HF_REPO="bartowski/gemma-2-2b-it-GGUF:Q4_K_M"
      LLAMA_ALIAS="gemma-2-2b-it"
      BRAIN_THREADS_DEFAULT="4"
      BRAIN_CONTEXT_DEFAULT="2048"
      BRAIN_BATCH_DEFAULT="192"
      BRAIN_UBATCH_DEFAULT="96"
      BRAIN_MAX_MESSAGES_DEFAULT="8"
      ;;
    4)
      LLM_PROVIDER="llama.cpp"
      BRAIN_PROFILE_NAME="custom"
      BRAIN_PROFILE_LABEL="Custom"
      LLAMA_HF_REPO=$(prompt_value "Enter custom llama.cpp HF repo[:quant]" "bartowski/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M")
      LLAMA_ALIAS=$(prompt_value "Enter model alias to expose via llama-server" "custom-local-model")
      BRAIN_THREADS_DEFAULT="4"
      BRAIN_CONTEXT_DEFAULT="2048"
      BRAIN_BATCH_DEFAULT="256"
      BRAIN_UBATCH_DEFAULT="128"
      BRAIN_MAX_MESSAGES_DEFAULT="12"
      ;;
    *)
      die "Invalid model choice"
      ;;
  esac
}

pick_llm_runtime_mode() {
  local choice
  choice=$(choose_from_menu \
    "Select the LLM runtime mode" \
    "1" \
    "1|Local llama.cpp on the Raspberry Pi (offline)" \
    "2|Ollama on another computer in your LAN (free, no API key)" \
    "3|DeepSeek API via OpenAI-compatible endpoint (online)" \
    "4|Ollama Cloud via ollama.com API")

  case "${choice}" in
    1)
      LLM_SERVER_SELECTION="llama.cpp"
      LLM_PROVIDER="llama.cpp"
      SERVE_LLAMA_CPP_VALUE="true"
      SERVE_OLLAMA_VALUE="false"
      ;;
    2)
      LLM_SERVER_SELECTION="ollama"
      LLM_PROVIDER="ollama"
      SERVE_LLAMA_CPP_VALUE="false"
      SERVE_OLLAMA_VALUE="false"
      OLLAMA_ENDPOINT_VALUE=$(prompt_value "Enter Ollama endpoint on your LAN" "http://192.168.1.100:11434")
      OLLAMA_MODEL_VALUE=$(prompt_value "Enter Ollama model name" "gemma3:4b")
      OLLAMA_ENABLE_TOOLS_VALUE="false"
      BRAIN_PROFILE_NAME="lan-ollama"
      BRAIN_PROFILE_LABEL="LAN Ollama"
      if prompt_yes_no "Skip local llama.cpp install and model pre-download for this Ollama setup" "y"; then
        INSTALL_LLAMA_CPP=false
        DOWNLOAD_LLM_MODEL=false
      fi
      ;;
    3)
      LLM_SERVER_SELECTION="openai"
      LLM_PROVIDER="openai"
      SERVE_LLAMA_CPP_VALUE="false"
      SERVE_OLLAMA_VALUE="false"
      OPENAI_API_BASE_URL_VALUE=$(prompt_value "Enter OpenAI-compatible API base URL" "https://api.deepseek.com/v1")
      OPENAI_API_KEY_VALUE=$(prompt_required_value "Enter DeepSeek/OpenAI-compatible API key")
      OPENAI_LLM_MODEL_VALUE=$(prompt_value "Enter online model name" "deepseek-chat")
      OPENAI_ENABLE_TOOLS_VALUE="false"
      BRAIN_PROFILE_NAME="deepseek-api"
      BRAIN_PROFILE_LABEL="DeepSeek API"
      if prompt_yes_no "Skip local llama.cpp install and model pre-download for this online setup" "y"; then
        INSTALL_LLAMA_CPP=false
        DOWNLOAD_LLM_MODEL=false
      fi
      ;;
    4)
      LLM_SERVER_SELECTION="ollama-cloud"
      LLM_PROVIDER="ollama-cloud"
      SERVE_LLAMA_CPP_VALUE="false"
      SERVE_OLLAMA_VALUE="false"
      OLLAMA_ENDPOINT_VALUE=$(prompt_value "Enter Ollama Cloud API endpoint" "https://ollama.com")
      OLLAMA_MODEL_VALUE=$(prompt_value "Enter Ollama Cloud model name" "gemma3:27b-cloud")
      OLLAMA_API_KEY_VALUE=$(prompt_required_value "Enter OLLAMA_API_KEY")
      OLLAMA_ENABLE_TOOLS_VALUE="false"
      BRAIN_PROFILE_NAME="ollama-cloud"
      BRAIN_PROFILE_LABEL="Ollama Cloud"
      if prompt_yes_no "Skip local llama.cpp install and model pre-download for this cloud setup" "y"; then
        INSTALL_LLAMA_CPP=false
        DOWNLOAD_LLM_MODEL=false
      fi
      ;;
    *)
      die "Invalid LLM runtime choice"
      ;;
  esac
}

pick_asr_model() {
  local choice
  choice=$(choose_from_menu \
    "Select the faster-whisper ASR model" \
    "1" \
    "1|tiny (fastest, recommended)" \
    "2|base" \
    "3|custom local path")
  case "${choice}" in
    1) ASR_MODEL="tiny" ;;
    2) ASR_MODEL="base" ;;
    3) ASR_MODEL=$(prompt_value "Enter faster-whisper model name or local directory" "tiny") ;;
    *) die "Invalid ASR choice" ;;
  esac
}

pick_tts_voice() {
  local choice
  choice=$(choose_from_menu \
    "Select the Piper voice" \
    "1" \
    "1|English: en_US-lessac-medium (recommended)" \
    "2|Polish: pl_PL-gosia-medium" \
    "3|German: de_DE-thorsten-medium" \
    "4|custom voice id")
  case "${choice}" in
    1)
      PIPER_VOICE="en_US-lessac-medium"
      ASR_LANGUAGE="en"
      ASSISTANT_SYSTEM_PROMPT="You are a practical voice assistant running on a Raspberry Pi. Reply in English unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess."
      ;;
    2)
      PIPER_VOICE="pl_PL-gosia-medium"
      ASR_LANGUAGE="pl"
      ASSISTANT_SYSTEM_PROMPT="You are a practical voice assistant running on a Raspberry Pi. Always reply in Polish unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess."
      ;;
    3)
      PIPER_VOICE="de_DE-thorsten-medium"
      ASR_LANGUAGE="de"
      ASSISTANT_SYSTEM_PROMPT="You are a practical voice assistant running on a Raspberry Pi. Always reply in German unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess."
      ;;
    4)
      PIPER_VOICE=$(prompt_value "Enter Piper voice id" "en_US-lessac-medium")
      ASR_LANGUAGE=$(prompt_value "Enter faster-whisper language code (en/pl/de or empty for auto)" "en")
      ASSISTANT_SYSTEM_PROMPT=$(prompt_value "Enter assistant language instruction" "You are a practical voice assistant running on a Raspberry Pi. Reply in English unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess.")
      ;;
    *) die "Invalid Piper voice choice" ;;
  esac
}

pick_polish_quality_mode() {
  if [ "${ASR_LANGUAGE}" != "pl" ] || [ "${LLM_SERVER_SELECTION}" != "llama.cpp" ]; then
    return 0
  fi

  local choice
  choice=$(choose_from_menu \
    "Select the free Polish quality mode" \
    "1" \
    "1|Pi-only stronger local mode (recommended): small faster-whisper + Gemma 2 2B" \
    "2|Better free quality via Ollama on another computer in your LAN" \
    "3|Keep my manual brain / ASR choices")

  case "${choice}" in
    1)
      ASR_MODEL="small"
      BRAIN_PROFILE_NAME="quality"
      BRAIN_PROFILE_LABEL="Higher quality"
      LLAMA_HF_REPO="bartowski/gemma-2-2b-it-GGUF:Q4_K_M"
      LLAMA_ALIAS="gemma-2-2b-it"
      BRAIN_THREADS_DEFAULT="4"
      BRAIN_CONTEXT_DEFAULT="2048"
      BRAIN_BATCH_DEFAULT="192"
      BRAIN_UBATCH_DEFAULT="96"
      BRAIN_MAX_MESSAGES_DEFAULT="8"
      LLM_SERVER_SELECTION="llama.cpp"
      SERVE_LLAMA_CPP_VALUE="true"
      SERVE_OLLAMA_VALUE="false"
      ;;
    2)
      ASR_MODEL="small"
      LLM_SERVER_SELECTION="ollama"
      SERVE_LLAMA_CPP_VALUE="false"
      SERVE_OLLAMA_VALUE="false"
      OLLAMA_ENDPOINT_VALUE=$(prompt_value "Enter Ollama endpoint on your LAN" "http://192.168.1.100:11434")
      OLLAMA_MODEL_VALUE=$(prompt_value "Enter Ollama model name" "gemma3:4b")
      OLLAMA_ENABLE_TOOLS_VALUE="false"
      BRAIN_PROFILE_NAME="lan-ollama"
      BRAIN_PROFILE_LABEL="LAN Ollama"
      if prompt_yes_no "Skip local llama.cpp install and model pre-download for this LAN Ollama setup" "y"; then
        INSTALL_LLAMA_CPP=false
        DOWNLOAD_LLM_MODEL=false
      fi
      ;;
    3)
      ;;
    *)
      die "Invalid Polish quality mode choice"
      ;;
  esac
}

pick_wake_word_config() {
  local choice
  choice=$(choose_from_menu \
    "Select wake word engine" \
    "1" \
    "1|openWakeWord (recommended for a ready-made English wake word like hey_jarvis)" \
    "2|local-wake (custom phrase from your own recordings)")
  case "${choice}" in
    1)
      WAKE_WORD_ENGINE="openwakeword"
      local oww_choice
      oww_choice=$(choose_from_menu \
        "Select the English preset wake word" \
        "1" \
        "1|hey_jarvis" \
        "2|hey_mycroft" \
        "3|hey_rhasspy" \
        "4|alexa")
      case "${oww_choice}" in
        1) WAKE_WORD_OPENWAKEWORD_MODEL="hey_jarvis" ;;
        2) WAKE_WORD_OPENWAKEWORD_MODEL="hey_mycroft" ;;
        3) WAKE_WORD_OPENWAKEWORD_MODEL="hey_rhasspy" ;;
        4) WAKE_WORD_OPENWAKEWORD_MODEL="alexa" ;;
        *) die "Invalid openWakeWord choice" ;;
      esac
      WAKE_WORD_THRESHOLD=$(prompt_value "openWakeWord confidence threshold" "0.45")
      WAKE_WORD_VAD_THRESHOLD=$(prompt_value "openWakeWord VAD threshold" "0.2")
      if prompt_yes_no "Enable Speex noise suppression for openWakeWord" "y"; then
        WAKE_WORD_ENABLE_SPEEX="true"
      else
        WAKE_WORD_ENABLE_SPEEX="false"
      fi
      ;;
    2)
      WAKE_WORD_ENGINE="local-wake"
      local phrase_choice
      phrase_choice=$(choose_from_menu \
        "Select the wake phrase label" \
        "1" \
        "1|hey whisplay" \
        "2|hello assistant" \
        "3|computer" \
        "4|custom phrase")
      case "${phrase_choice}" in
        1) WAKE_WORD_PHRASE="hey whisplay" ;;
        2) WAKE_WORD_PHRASE="hello assistant" ;;
        3) WAKE_WORD_PHRASE="computer" ;;
        4) WAKE_WORD_PHRASE=$(prompt_value "Enter custom wake phrase" "hey whisplay") ;;
        *) die "Invalid wake phrase choice" ;;
      esac
      WAKE_WORD_THRESHOLD=$(prompt_value "local-wake distance threshold (lower is stricter)" "0.16")
      WAKE_WORD_BUFFER_SIZE=$(prompt_value "local-wake buffer size (seconds)" "1.8")
      WAKE_WORD_SLIDE_SIZE=$(prompt_value "local-wake slide size (seconds)" "0.25")
      WAKE_WORD_SAMPLE_COUNT=$(prompt_value "Number of reference recordings" "4")
      WAKE_WORD_SAMPLE_DURATION=$(prompt_value "Duration of each reference recording (seconds, whole numbers work best)" "3")
      WAKE_WORD_REFERENCE_DIR="${PROJECT_ROOT}/data/wakewords/$(slugify "${WAKE_WORD_PHRASE}")"
      if prompt_yes_no "Record wake word samples during install" "y"; then
        RECORD_WAKE_WORD_SAMPLES=true
      fi
      ;;
    *)
      die "Invalid wake word engine choice"
      ;;
  esac
}

if [ "$(uname -s)" != "Linux" ]; then
  die "This installer must run on Raspberry Pi OS"
fi

if [ ! -f /proc/device-tree/model ] || ! grep -q "Raspberry Pi" /proc/device-tree/model; then
  die "This installer targets Raspberry Pi hardware only"
fi

if ! command -v git >/dev/null 2>&1; then
  log "Installing git"
  sudo apt-get update
  sudo apt-get install -y git
fi

while true; do
  reset_install_choices

  print_intro
  print_section "Select install components"
  print_note "Choose what should be installed or prepared on this Pi."

  if prompt_yes_no "Install Whisplay HAT driver" "y"; then INSTALL_DRIVER=true; fi
  if prompt_yes_no "Install chatbot dependencies (Node, Python, fonts)" "y"; then INSTALL_CHATBOT_DEPS=true; fi
  if prompt_yes_no "Build and install llama.cpp server" "y"; then INSTALL_LLAMA_CPP=true; fi
  if prompt_yes_no "Install local ASR (faster-whisper)" "y"; then INSTALL_LOCAL_ASR=true; fi
  if prompt_yes_no "Install local TTS (Piper HTTP)" "y"; then INSTALL_LOCAL_TTS=true; fi
  if prompt_yes_no "Install wake word detection" "y"; then INSTALL_WAKE_WORD=true; fi
  if prompt_yes_no "Build chatbot TypeScript app" "y"; then BUILD_CHATBOT=true; fi
  if prompt_yes_no "Install chatbot systemd service" "y"; then INSTALL_SERVICE=true; fi
  if [ "${INSTALL_LLAMA_CPP}" = true ] || [ -d "${PREFERRED_LLAMA_DIR}" ] || [ -x "/usr/local/bin/llama-server" ]; then
    if prompt_yes_no "Pre-download llama.cpp model during install" "y"; then DOWNLOAD_LLM_MODEL=true; fi
  fi
  if [ "${INSTALL_LOCAL_ASR}" = true ]; then
    if prompt_yes_no "Pre-download faster-whisper model during install" "y"; then DOWNLOAD_ASR_MODEL=true; fi
  fi

  pick_asr_model
  pick_tts_voice
  pick_llm_runtime_mode
  if [ "${LLM_SERVER_SELECTION}" = "llama.cpp" ]; then
    pick_llm_repo
    pick_llama_hf_auth
  fi
  pick_polish_quality_mode
  if [ "${INSTALL_WAKE_WORD}" = true ]; then
    pick_wake_word_config
  fi

  print_section "Configuration summary"
  if [ "${LLM_SERVER_SELECTION}" = "ollama" ]; then
    log "Selected brain profile: ${BRAIN_PROFILE_LABEL}"
    log "LLM mode: Ollama on LAN (${OLLAMA_ENDPOINT_VALUE}, model ${OLLAMA_MODEL_VALUE})"
  elif [ "${LLM_SERVER_SELECTION}" = "openai" ]; then
    log "Selected brain profile: ${BRAIN_PROFILE_LABEL}"
    log "LLM mode: online OpenAI-compatible endpoint (${OPENAI_API_BASE_URL_VALUE}, model ${OPENAI_LLM_MODEL_VALUE})"
  elif [ "${LLM_SERVER_SELECTION}" = "ollama-cloud" ]; then
    log "Selected brain profile: ${BRAIN_PROFILE_LABEL}"
    log "LLM mode: Ollama Cloud (${OLLAMA_ENDPOINT_VALUE}, model ${OLLAMA_MODEL_VALUE})"
  else
    log "Selected brain profile: ${BRAIN_PROFILE_LABEL}"
    log "Brain model: ${LLAMA_HF_REPO}"
  fi

  DRIVER_DIR=$(prompt_value "Whisplay driver repo directory" "${PREFERRED_DRIVER_DIR}")
  LLAMA_DIR="${PREFERRED_LLAMA_DIR}"
  PIPER_DIR=$(prompt_value "Piper model directory" "${DEFAULT_PIPER_DIR}")

  CHATBOT_THREADS="${BRAIN_THREADS_DEFAULT:-4}"
  CHATBOT_CONTEXT="${BRAIN_CONTEXT_DEFAULT:-2048}"
  CHATBOT_BATCH="${BRAIN_BATCH_DEFAULT:-256}"
  CHATBOT_UBATCH="${BRAIN_UBATCH_DEFAULT:-128}"
  CHATBOT_MAX_MESSAGES="${BRAIN_MAX_MESSAGES_DEFAULT:-12}"
  if [ "${LLM_SERVER_SELECTION}" = "llama.cpp" ]; then
    LLAMA_DIR=$(prompt_value "llama.cpp repo directory" "${PREFERRED_LLAMA_DIR}")
    CHATBOT_THREADS=$(prompt_value "llama.cpp CPU threads" "${CHATBOT_THREADS}")
    CHATBOT_CONTEXT=$(prompt_value "llama.cpp context size" "${CHATBOT_CONTEXT}")
    CHATBOT_BATCH=$(prompt_value "llama.cpp batch size" "${CHATBOT_BATCH}")
    CHATBOT_UBATCH=$(prompt_value "llama.cpp ubatch size" "${CHATBOT_UBATCH}")
  fi
  CHATBOT_MAX_MESSAGES=$(prompt_value "chat history message limit" "${CHATBOT_MAX_MESSAGES}")

  print_final_review
  review_action=$(choose_from_menu \
    "Review action" \
    "1" \
    "1|Proceed with installation" \
    "2|Go back and edit choices" \
    "3|Cancel")
  case "${review_action}" in
    1)
      break
      ;;
    2)
      print_note "Restarting the configuration prompts with your installer defaults."
      continue
      ;;
    3)
      die "Installation cancelled by user."
      ;;
  esac
done


if [ ! -f "${CHATBOT_ENV_TEMPLATE}" ]; then
  die "Missing ${CHATBOT_ENV_TEMPLATE}"
fi

if [ -f "${CHATBOT_ENV_FILE}" ]; then
  backup_file="${CHATBOT_ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
  cp "${CHATBOT_ENV_FILE}" "${backup_file}"
  log "Backed up existing .env to ${backup_file}"
fi

cp "${CHATBOT_ENV_TEMPLATE}" "${CHATBOT_ENV_FILE}"
set_env_value "${CHATBOT_ENV_FILE}" "ASR_SERVER" "faster-whisper"
set_env_value "${CHATBOT_ENV_FILE}" "LLM_SERVER" "${LLM_SERVER_SELECTION}"
set_env_value "${CHATBOT_ENV_FILE}" "TTS_SERVER" "piper-http"
set_env_value "${CHATBOT_ENV_FILE}" "SERVE_LLAMA_CPP" "${SERVE_LLAMA_CPP_VALUE}"
set_env_value "${CHATBOT_ENV_FILE}" "SERVE_OLLAMA" "${SERVE_OLLAMA_VALUE}"
if [ "${LLM_SERVER_SELECTION}" = "llama.cpp" ]; then
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_HF_REPO" "${LLAMA_HF_REPO}"
  if [ -n "${LLAMA_CPP_HF_TOKEN_VALUE:-}" ]; then
    set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_HF_TOKEN" "${LLAMA_CPP_HF_TOKEN_VALUE}"
    set_env_value "${CHATBOT_ENV_FILE}" "HF_TOKEN" "${LLAMA_CPP_HF_TOKEN_VALUE}"
  fi
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_MODEL" "${LLAMA_ALIAS}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_ALIAS" "${LLAMA_ALIAS}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_THREADS" "${CHATBOT_THREADS}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_CONTEXT_SIZE" "${CHATBOT_CONTEXT}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_BATCH_SIZE" "${CHATBOT_BATCH}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_UBATCH_SIZE" "${CHATBOT_UBATCH}"
fi
set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_MAX_MESSAGES_LENGTH" "${CHATBOT_MAX_MESSAGES}"
set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_ENABLE_TOOLS" "false"

set_env_value "${CHATBOT_ENV_FILE}" "FASTER_WHISPER_MODEL_SIZE_OR_PATH" "${ASR_MODEL}"
set_env_value "${CHATBOT_ENV_FILE}" "FASTER_WHISPER_LANGUAGE" "${ASR_LANGUAGE}"
set_env_value "${CHATBOT_ENV_FILE}" "PIPER_HTTP_MODEL" "${PIPER_DIR}/${PIPER_VOICE}"
set_env_value "${CHATBOT_ENV_FILE}" "SYSTEM_PROMPT" "${ASSISTANT_SYSTEM_PROMPT}"
if [ "${LLM_SERVER_SELECTION}" = "ollama" ]; then
  set_env_value "${CHATBOT_ENV_FILE}" "OLLAMA_ENDPOINT" "${OLLAMA_ENDPOINT_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "OLLAMA_MODEL" "${OLLAMA_MODEL_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "OLLAMA_ENABLE_TOOLS" "${OLLAMA_ENABLE_TOOLS_VALUE}"
elif [ "${LLM_SERVER_SELECTION}" = "openai" ]; then
  set_env_value "${CHATBOT_ENV_FILE}" "OPENAI_API_BASE_URL" "${OPENAI_API_BASE_URL_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "OPENAI_API_KEY" "${OPENAI_API_KEY_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "OPENAI_LLM_MODEL" "${OPENAI_LLM_MODEL_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "OPENAI_ENABLE_TOOLS" "${OPENAI_ENABLE_TOOLS_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "OPENAI_MAX_MESSAGES_LENGTH" "${CHATBOT_MAX_MESSAGES}"
fi
if [ "${INSTALL_WAKE_WORD}" = true ]; then
  set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_ENABLED" "true"
  set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_ENGINE" "${WAKE_WORD_ENGINE}"
  set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_THRESHOLD" "${WAKE_WORD_THRESHOLD}"
  if [ "${WAKE_WORD_ENGINE}" = "local-wake" ]; then
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_PHRASE" "${WAKE_WORD_PHRASE}"
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_REFERENCE_DIR" "${WAKE_WORD_REFERENCE_DIR}"
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_LOCAL_WAKE_BUFFER_SIZE" "${WAKE_WORD_BUFFER_SIZE}"
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_LOCAL_WAKE_SLIDE_SIZE" "${WAKE_WORD_SLIDE_SIZE}"
  else
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORDS" "${WAKE_WORD_OPENWAKEWORD_MODEL}"
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_VAD_THRESHOLD" "${WAKE_WORD_VAD_THRESHOLD:-0.2}"
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_ENABLE_SPEEX" "${WAKE_WORD_ENABLE_SPEEX:-true}"
  fi
else
  set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_ENABLED" "false"
fi

if [ "${LLM_PROVIDER}" = "ollama-cloud" ]; then
  set_env_value "${CHATBOT_ENV_FILE}" "LLM_SERVER" "ollama-cloud"
  set_env_value "${CHATBOT_ENV_FILE}" "OLLAMA_ENDPOINT" "${OLLAMA_ENDPOINT_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "OLLAMA_MODEL" "${OLLAMA_MODEL_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "OLLAMA_API_KEY" "${OLLAMA_API_KEY_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "SERVE_LLAMA_CPP" "false"
elif [ "${LLM_SERVER_SELECTION}" = "llama.cpp" ]; then
  set_env_value "${CHATBOT_ENV_FILE}" "LLM_SERVER" "llama.cpp"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_HF_REPO" "${LLAMA_HF_REPO}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_MODEL" "${LLAMA_ALIAS}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_ALIAS" "${LLAMA_ALIAS}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_THREADS" "${CHATBOT_THREADS}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_CONTEXT_SIZE" "${CHATBOT_CONTEXT}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_BATCH_SIZE" "${CHATBOT_BATCH}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_UBATCH_SIZE" "${CHATBOT_UBATCH}"
  set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_MAX_MESSAGES_LENGTH" "${CHATBOT_MAX_MESSAGES}"
fi

if [ "${INSTALL_DRIVER}" = true ]; then
  ensure_repo "${DRIVER_DIR}" "${DRIVER_REPO_URL}" "Whisplay driver"
  patch_whisplay_driver_installer "${DRIVER_DIR}"
  log "Installing WM8960 driver"
  cd "${DRIVER_DIR}/Driver"
  sudo bash install_wm8960_drive.sh
  cd "${PROJECT_ROOT}"
  DRIVER_REBOOT_RECOMMENDED=true
fi

if [ "${INSTALL_CHATBOT_DEPS}" = true ]; then
  log "Installing chatbot dependencies"
  cd "${PROJECT_ROOT}"
  bash install_dependencies.sh
fi

chmod +x "${PROJECT_ROOT}/scripts/serve_llama_cpp.sh" "${PROJECT_ROOT}/scripts/install_llama_cpp.sh" 2>/dev/null || true

if [ "${INSTALL_LOCAL_ASR}" = true ]; then
  log "Installing faster-whisper dependencies"
  python3 -m pip install --break-system-packages faster-whisper Flask
fi

if [ "${INSTALL_WAKE_WORD}" = true ]; then
  if [ "${WAKE_WORD_ENGINE}" = "local-wake" ]; then
    install_local_wake_runtime
  else
    install_openwakeword_runtime
  fi
fi

if [ "${DOWNLOAD_ASR_MODEL}" = true ]; then
  download_faster_whisper_model
fi

if [ "${INSTALL_LOCAL_TTS}" = true ]; then
  log "Installing Piper HTTP dependencies"
  python3 -m pip install --break-system-packages piper-tts==1.3.0 'piper-tts[http]'
  mkdir -p "${PIPER_DIR}"
  (
    cd "${PIPER_DIR}"
    python3 -m piper.download_voices "${PIPER_VOICE}"
  )
fi

if [ "${INSTALL_LLAMA_CPP}" = true ]; then
  ensure_repo "${LLAMA_DIR}" "${LLAMA_REPO_URL}" "llama.cpp"
  log "Building llama.cpp"
  LLAMA_CPP_REPO_DIR="${LLAMA_DIR}" bash "${PROJECT_ROOT}/scripts/install_llama_cpp.sh"
fi

if [ "${DOWNLOAD_LLM_MODEL}" = true ]; then
  if ! download_llama_cpp_model; then
    warn "Skipping llama.cpp pre-download. The assistant can still work; the first model start may just take longer."
    warn "If needed later, start the chatbot once or run /usr/local/bin/llama-server -hf ${LLAMA_HF_REPO} manually on the Pi to populate the cache."
  fi
fi

if [ "${BUILD_CHATBOT}" = true ]; then
  log "Building chatbot"
  cd "${PROJECT_ROOT}"
  bash build.sh
fi

if [ "${INSTALL_SERVICE}" = true ]; then
  log "Installing chatbot service"
  cd "${PROJECT_ROOT}"
  bash startup.sh
fi

if [ "${INSTALL_WAKE_WORD}" = true ] && [ "${WAKE_WORD_ENGINE}" = "local-wake" ] && [ "${RECORD_WAKE_WORD_SAMPLES}" = true ]; then
  log "Recording local-wake reference samples for '${WAKE_WORD_PHRASE}'"
  record_local_wake_samples "${WAKE_WORD_REFERENCE_DIR}" "${WAKE_WORD_SAMPLE_COUNT}" "${WAKE_WORD_SAMPLE_DURATION}" "${WAKE_WORD_PHRASE}"
fi

if [ "${INSTALL_WAKE_WORD}" = true ] && [ "${WAKE_WORD_ENGINE}" = "local-wake" ]; then
  if ! compgen -G "${WAKE_WORD_REFERENCE_DIR}/*.wav" >/dev/null 2>&1; then
    warn "Wake word is enabled, but no local-wake samples were found in ${WAKE_WORD_REFERENCE_DIR}."
    warn "Record samples with: bash scripts/setup_local_wakeword.sh 4 3"
  fi
fi

log "Install complete"
log "Configured .env: ${CHATBOT_ENV_FILE}"
log "Brain profile prepared: ${BRAIN_PROFILE_LABEL}"
if [ "${INSTALL_WAKE_WORD}" = true ]; then
  if [ "${WAKE_WORD_ENGINE}" = "local-wake" ]; then
    log "Wake word enabled with local-wake phrase '${WAKE_WORD_PHRASE}'"
    log "Reference directory: ${WAKE_WORD_REFERENCE_DIR}"
  else
    log "Wake word enabled with openWakeWord model '${WAKE_WORD_OPENWAKEWORD_MODEL}'"
  fi
fi
if [ "${DRIVER_REBOOT_RECOMMENDED}" = true ]; then
  log "Driver install completed. Reboot the Pi before expecting audio hardware to work correctly."
fi
log "Recommended first run: bash run_chatbot.sh"
