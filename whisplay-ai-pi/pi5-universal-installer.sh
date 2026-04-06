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

log() {
  echo "[pi5-installer] $*"
}

die() {
  echo "[pi5-installer] $*" >&2
  exit 1
}

prompt_yes_no() {
  local prompt="$1"
  local default_value="$2"
  local reply
  while true; do
    read -r -p "${prompt} [${default_value}] " reply
    reply="${reply:-$default_value}"
    case "${reply}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
    esac
  done
}

prompt_value() {
  local prompt="$1"
  local default_value="$2"
  local reply
  read -r -p "${prompt} [${default_value}] " reply
  printf '%s\n' "${reply:-$default_value}"
}

set_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  if grep -Eq "^[# ]*${key}=" "${file}"; then
    sed -i "s|^[# ]*${key}=.*|${key}=${value}|" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
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
  python3 - <<PY
from faster_whisper import WhisperModel

model_name = ${ASR_MODEL@Q}
WhisperModel(model_name, device="cpu", compute_type="int8", cpu_threads=3)
print(f"faster-whisper model ready: {model_name}")
PY
}

download_llama_cpp_model() {
  local server_bin
  server_bin=$(find_llama_server_bin) || die "llama-server binary not found after install"

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
  llama_host="127.0.0.1"
  llama_port="18080"

  (
    LLAMA_CPP_SERVER_BIN="${server_bin}" \
    LLAMA_CPP_HOST="${llama_host}" \
    LLAMA_CPP_PORT="${llama_port}" \
    LLAMA_CPP_HF_REPO="${LLAMA_HF_REPO}" \
    LLAMA_CPP_ALIAS="${LLAMA_ALIAS}" \
    LLAMA_CPP_MODEL="${LLAMA_ALIAS}" \
    LLAMA_CPP_THREADS="${CHATBOT_THREADS}" \
    LLAMA_CPP_CONTEXT_SIZE="${CHATBOT_CONTEXT}" \
    LLAMA_CPP_ENABLE_TOOLS="false" \
    LLAMA_CPP_EXTRA_ARGS="--parallel 1" \
    bash "${PROJECT_ROOT}/scripts/serve_llama_cpp.sh"
  ) >/tmp/whisplay-llama-download.log 2>&1 &
  llama_pid=$!

  for _ in $(seq 1 120); do
    if curl -sf "http://${llama_host}:${llama_port}/v1/models" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 2
  done

  if [ "${ready}" -ne 1 ]; then
    kill "${llama_pid}" >/dev/null 2>&1 || true
    die "llama-server did not become ready. See /tmp/whisplay-llama-download.log"
  fi

  curl -sf "http://${llama_host}:${llama_port}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${LLAMA_ALIAS}\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}],\"stream\":false,\"max_tokens\":1}" \
    >/tmp/whisplay-llama-download-request.json

  kill "${llama_pid}" >/dev/null 2>&1 || true
  wait "${llama_pid}" 2>/dev/null || true
  log "llama.cpp model ready"
}

pick_llm_repo() {
  echo "Select the assistant brain profile:"
  echo "  1. Fast: Qwen2.5 0.5B Instruct Q4_K_M"
  echo "  2. Balanced: Qwen2.5 1.5B Instruct Q4_K_M (recommended)"
  echo "  3. Higher quality: Gemma 2 2B Instruct Q4_K_M"
  echo "  4. Custom Hugging Face GGUF repo"
  local choice
  read -r -p "Choice [2] " choice
  choice="${choice:-2}"
  case "${choice}" in
    1)
      BRAIN_PROFILE_NAME="fast"
      BRAIN_PROFILE_LABEL="Fast"
      LLAMA_HF_REPO="ggml-org/Qwen2.5-0.5B-Instruct-GGUF:Q4_K_M"
      LLAMA_ALIAS="qwen2.5-0.5b-instruct"
      BRAIN_THREADS_DEFAULT="4"
      BRAIN_CONTEXT_DEFAULT="1536"
      BRAIN_BATCH_DEFAULT="192"
      BRAIN_UBATCH_DEFAULT="96"
      BRAIN_MAX_MESSAGES_DEFAULT="10"
      ;;
    2)
      BRAIN_PROFILE_NAME="balanced"
      BRAIN_PROFILE_LABEL="Balanced"
      LLAMA_HF_REPO="ggml-org/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M"
      LLAMA_ALIAS="qwen2.5-1.5b-instruct"
      BRAIN_THREADS_DEFAULT="4"
      BRAIN_CONTEXT_DEFAULT="2048"
      BRAIN_BATCH_DEFAULT="256"
      BRAIN_UBATCH_DEFAULT="128"
      BRAIN_MAX_MESSAGES_DEFAULT="12"
      ;;
    3)
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
      BRAIN_PROFILE_NAME="custom"
      BRAIN_PROFILE_LABEL="Custom"
      LLAMA_HF_REPO=$(prompt_value "Enter custom llama.cpp HF repo[:quant]" "ggml-org/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M")
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

pick_asr_model() {
  echo "Select the faster-whisper ASR model:"
  echo "  1. tiny (fastest, recommended)"
  echo "  2. base"
  echo "  3. custom local path"
  local choice
  read -r -p "Choice [1] " choice
  choice="${choice:-1}"
  case "${choice}" in
    1) ASR_MODEL="tiny" ;;
    2) ASR_MODEL="base" ;;
    3) ASR_MODEL=$(prompt_value "Enter faster-whisper model name or local directory" "tiny") ;;
    *) die "Invalid ASR choice" ;;
  esac
}

pick_tts_voice() {
  echo "Select the Piper voice:"
  echo "  1. English: en_US-lessac-medium (recommended)"
  echo "  2. Polish: pl_PL-gosia-medium"
  echo "  3. German: de_DE-thorsten-medium"
  echo "  4. custom voice id"
  local choice
  read -r -p "Choice [1] " choice
  choice="${choice:-1}"
  case "${choice}" in
    1) PIPER_VOICE="en_US-lessac-medium" ;;
    2) PIPER_VOICE="pl_PL-gosia-medium" ;;
    3) PIPER_VOICE="de_DE-thorsten-medium" ;;
    4) PIPER_VOICE=$(prompt_value "Enter Piper voice id" "en_US-lessac-medium") ;;
    *) die "Invalid Piper voice choice" ;;
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

INSTALL_DRIVER=false
INSTALL_CHATBOT_DEPS=false
INSTALL_LLAMA_CPP=false
INSTALL_LOCAL_ASR=false
INSTALL_LOCAL_TTS=false
BUILD_CHATBOT=false
INSTALL_SERVICE=false
DOWNLOAD_LLM_MODEL=false
DOWNLOAD_ASR_MODEL=false

if prompt_yes_no "Install Whisplay HAT driver" "y"; then INSTALL_DRIVER=true; fi
if prompt_yes_no "Install chatbot dependencies (Node, Python, fonts)" "y"; then INSTALL_CHATBOT_DEPS=true; fi
if prompt_yes_no "Build and install llama.cpp server" "y"; then INSTALL_LLAMA_CPP=true; fi
if prompt_yes_no "Install local ASR (faster-whisper)" "y"; then INSTALL_LOCAL_ASR=true; fi
if prompt_yes_no "Install local TTS (Piper HTTP)" "y"; then INSTALL_LOCAL_TTS=true; fi
if prompt_yes_no "Build chatbot TypeScript app" "y"; then BUILD_CHATBOT=true; fi
if prompt_yes_no "Install chatbot systemd service" "y"; then INSTALL_SERVICE=true; fi
if [ "${INSTALL_LLAMA_CPP}" = true ] || [ -d "${PREFERRED_LLAMA_DIR}" ] || [ -x "/usr/local/bin/llama-server" ]; then
  if prompt_yes_no "Pre-download llama.cpp model during install" "y"; then DOWNLOAD_LLM_MODEL=true; fi
fi
if [ "${INSTALL_LOCAL_ASR}" = true ]; then
  if prompt_yes_no "Pre-download faster-whisper model during install" "y"; then DOWNLOAD_ASR_MODEL=true; fi
fi

pick_llm_repo
pick_asr_model
pick_tts_voice

log "Selected brain profile: ${BRAIN_PROFILE_LABEL}"
log "Brain model: ${LLAMA_HF_REPO}"

CHATBOT_ENV_TEMPLATE="${PROJECT_ROOT}/.env.pi5-local.template"
CHATBOT_ENV_FILE="${PROJECT_ROOT}/.env"
DRIVER_DIR=$(prompt_value "Whisplay driver repo directory" "${PREFERRED_DRIVER_DIR}")
LLAMA_DIR=$(prompt_value "llama.cpp repo directory" "${PREFERRED_LLAMA_DIR}")
PIPER_DIR=$(prompt_value "Piper model directory" "${DEFAULT_PIPER_DIR}")
CHATBOT_THREADS=$(prompt_value "llama.cpp CPU threads" "${BRAIN_THREADS_DEFAULT}")
CHATBOT_CONTEXT=$(prompt_value "llama.cpp context size" "${BRAIN_CONTEXT_DEFAULT}")
CHATBOT_BATCH=$(prompt_value "llama.cpp batch size" "${BRAIN_BATCH_DEFAULT}")
CHATBOT_UBATCH=$(prompt_value "llama.cpp ubatch size" "${BRAIN_UBATCH_DEFAULT}")
CHATBOT_MAX_MESSAGES=$(prompt_value "chat history message limit" "${BRAIN_MAX_MESSAGES_DEFAULT}")

if [ ! -f "${CHATBOT_ENV_TEMPLATE}" ]; then
  die "Missing ${CHATBOT_ENV_TEMPLATE}"
fi

if [ -f "${CHATBOT_ENV_FILE}" ]; then
  backup_file="${CHATBOT_ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
  cp "${CHATBOT_ENV_FILE}" "${backup_file}"
  log "Backed up existing .env to ${backup_file}"
fi

cp "${CHATBOT_ENV_TEMPLATE}" "${CHATBOT_ENV_FILE}"
set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_HF_REPO" "${LLAMA_HF_REPO}"
set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_MODEL" "${LLAMA_ALIAS}"
set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_ALIAS" "${LLAMA_ALIAS}"
set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_THREADS" "${CHATBOT_THREADS}"
set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_CONTEXT_SIZE" "${CHATBOT_CONTEXT}"
set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_BATCH_SIZE" "${CHATBOT_BATCH}"
set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_UBATCH_SIZE" "${CHATBOT_UBATCH}"
set_env_value "${CHATBOT_ENV_FILE}" "LLAMA_CPP_MAX_MESSAGES_LENGTH" "${CHATBOT_MAX_MESSAGES}"
set_env_value "${CHATBOT_ENV_FILE}" "FASTER_WHISPER_MODEL_SIZE_OR_PATH" "${ASR_MODEL}"
set_env_value "${CHATBOT_ENV_FILE}" "PIPER_HTTP_MODEL" "${PIPER_DIR}/${PIPER_VOICE}"

if [ "${INSTALL_DRIVER}" = true ]; then
  ensure_repo "${DRIVER_DIR}" "${DRIVER_REPO_URL}" "Whisplay driver"
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

if [ "${INSTALL_LOCAL_ASR}" = true ]; then
  log "Installing faster-whisper dependencies"
  python3 -m pip install --break-system-packages faster-whisper Flask
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
  download_llama_cpp_model
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

log "Install complete"
log "Configured .env: ${CHATBOT_ENV_FILE}"
log "Brain profile prepared: ${BRAIN_PROFILE_LABEL}"
if [ "${DRIVER_REBOOT_RECOMMENDED}" = true ]; then
  log "Driver install completed. Reboot the Pi before expecting audio hardware to work correctly."
fi
log "Recommended first run: bash run_chatbot.sh"
