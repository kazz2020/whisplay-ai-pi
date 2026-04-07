#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT="${SCRIPT_DIR}"
PREFERRED_DRIVER_DIR="${PROJECT_ROOT}/../Whisplay-main"
PREFERRED_LLAMA_DIR="${PROJECT_ROOT}/../llama.cpp-master"
DRIVER_REPO_URL="https://github.com/PiSugar/whisplay.git"
LLAMA_REPO_URL="https://github.com/ggml-org/llama.cpp.git"
DEFAULT_PIPER_DIR="${HOME}/piper"
DEFAULT_SHERPA_ONNX_TTS_DIR="${HOME}/sherpa-onnx-tts"
DRIVER_REBOOT_RECOMMENDED=false
ASR_LANGUAGE="en"
ASR_LANGUAGE_LABEL="English"
ASSISTANT_LANGUAGE_LABEL="English"
ASSISTANT_SYSTEM_PROMPT="You are a practical voice assistant running on a Raspberry Pi. Reply in English unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess."
LLM_SERVER_SELECTION="llama.cpp"
LLM_PROVIDER="llama.cpp"
SERVE_LLAMA_CPP_VALUE="true"
SERVE_OLLAMA_VALUE="false"
SERVE_QDRANT_VALUE="false"
OLLAMA_ENDPOINT_VALUE="http://192.168.1.100:11434"
OLLAMA_MODEL_VALUE="gemma3:4b"
OLLAMA_ENABLE_TOOLS_VALUE="false"
OPENAI_API_BASE_URL_VALUE="https://api.deepseek.com/v1"
OPENAI_API_KEY_VALUE=""
OPENAI_LLM_MODEL_VALUE="deepseek-chat"
OPENAI_ENABLE_TOOLS_VALUE="false"
ENABLE_THINKING_VALUE="false"
USE_CAPTURED_IMAGE_IN_CHAT_VALUE="false"
LLAMA_CPP_HF_TOKEN_VALUE="${HF_TOKEN:-}"
ENABLE_RAG_VALUE="false"
EMBEDDING_SERVER_VALUE="ollama"
VECTOR_DB_SERVER_VALUE="qdrant"
EMBEDDING_RUNTIME_LABEL="LAN Ollama endpoint"
INSTALL_OLLAMA=false
DOWNLOAD_OLLAMA_EMBEDDING_MODEL=false
NATIVE_OLLAMA_FOR_EMBEDDINGS=false
APPLY_PI_MEMORY_TUNING=false
PI_MEMORY_PROFILE_LABEL="disabled"
PI_MEMORY_MODE_VALUE="balanced"
PI_ZRAM_PERCENT_VALUE="50"
PI_ZRAM_ALGO_VALUE="lz4"
PI_DISK_SWAP_MB_VALUE="1024"
PI_SWAPPINESS_VALUE="100"
PI_VFS_CACHE_PRESSURE_VALUE="150"
PI_DIRTY_BACKGROUND_RATIO_VALUE="2"
PI_DIRTY_RATIO_VALUE="10"
RUNTIME_MALLOC_ARENA_MAX_VALUE="2"
RUNTIME_MALLOC_TRIM_THRESHOLD_VALUE="131072"
QDRANT_HOST_VALUE="http://127.0.0.1:6333"
OLLAMA_EMBEDDING_ENDPOINT_VALUE="http://192.168.1.100:11434"
OLLAMA_EMBEDDING_MODEL_VALUE="nomic-embed-text"
RAG_KNOWLEDGE_SCORE_THRESHOLD_VALUE="0.60"
RAG_KNOWLEDGE_TOP_K_VALUE="5"
RAG_KNOWLEDGE_MAX_CHUNKS_VALUE="3"
RAG_KNOWLEDGE_MAX_CHUNKS_PER_SOURCE_VALUE="2"
RAG_KNOWLEDGE_MAX_CONTEXT_CHARS_VALUE="1800"
WAKE_WORD_ENGINE="disabled"
WAKE_WORD_PHRASE=""
WAKE_WORD_REFERENCE_DIR=""
WAKE_WORD_THRESHOLD="0.16"
WAKE_WORD_BUFFER_SIZE="1.8"
WAKE_WORD_SLIDE_SIZE="0.25"
WAKE_WORD_SAMPLE_COUNT="4"
WAKE_WORD_SAMPLE_DURATION="3"
WAKE_WORD_OPENWAKEWORD_MODEL="hey_jarvis"
WAKE_WORD_COOLDOWN_SEC="1.5"
WAKE_WORD_VAD_THRESHOLD="0.2"
WAKE_WORD_ENABLE_SPEEX="true"
WAKE_WORD_END_KEYWORDS_VALUE="byebye,goodbye,stop"
DOWNLOAD_OPENWAKEWORD_MODEL=false
RECORD_WAKE_WORD_SAMPLES=false
TTS_SERVER_SELECTION="piper-http"
TTS_PROFILE_LABEL="Piper HTTP"
SHERPA_ONNX_TTS_DIR="${DEFAULT_SHERPA_ONNX_TTS_DIR}"
SHERPA_ONNX_TTS_MODEL_PACKAGE="vits-piper-pl_PL-gosia-medium"
SHERPA_ONNX_TTS_MODEL_LABEL="Polish: pl_PL-gosia-medium"
SHERPA_ONNX_TTS_MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pl_PL-gosia-medium.tar.bz2"
SHERPA_ONNX_TTS_HOST_VALUE="127.0.0.1"
SHERPA_ONNX_TTS_PORT_VALUE="8809"
SHERPA_ONNX_TTS_NUM_THREADS_VALUE="2"
SHERPA_ONNX_TTS_PROVIDER_VALUE="cpu"
SHERPA_ONNX_TTS_SPEAKER_ID_VALUE="0"
SHERPA_ONNX_TTS_SPEED_VALUE="1.0"
DOWNLOAD_SHERPA_ONNX_TTS_MODEL=true

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
  print_review_item "Assistant language" "${ASSISTANT_LANGUAGE_LABEL}"
  print_review_item "ASR language" "${ASR_LANGUAGE}"
  print_review_item "TTS backend" "${TTS_PROFILE_LABEL}"
  if [ "${TTS_SERVER_SELECTION}" = "piper-http" ]; then
    print_review_item "Piper voice" "${PIPER_VOICE}"
    print_review_item "Piper dir" "${PIPER_DIR}"
  else
    print_review_item "Sherpa model" "${SHERPA_ONNX_TTS_MODEL_LABEL}"
    print_review_item "Sherpa dir" "${SHERPA_ONNX_TTS_DIR}"
    print_review_item "Sherpa port" "${SHERPA_ONNX_TTS_PORT_VALUE}"
    print_review_item "Pre-download TTS" "$(format_enabled "${DOWNLOAD_SHERPA_ONNX_TTS_MODEL}")"
  fi
  print_review_item "Thinking mode" "${ENABLE_THINKING_VALUE}"
  print_review_item "Use camera in chat" "${USE_CAPTURED_IMAGE_IN_CHAT_VALUE}"
  print_review_item "Chat history limit" "${CHATBOT_MAX_MESSAGES}"
  print_review_item "Pi memory tuning" "${PI_MEMORY_PROFILE_LABEL}"
  if [ "${APPLY_PI_MEMORY_TUNING}" = true ]; then
    print_review_item "Memory mode" "${PI_MEMORY_MODE_VALUE}"
    print_review_item "ZRAM / swap" "${PI_ZRAM_PERCENT_VALUE}% / ${PI_DISK_SWAP_MB_VALUE} MB"
    print_review_item "Swappiness" "${PI_SWAPPINESS_VALUE}"
    print_review_item "Cache / dirty" "${PI_VFS_CACHE_PRESSURE_VALUE} / ${PI_DIRTY_BACKGROUND_RATIO_VALUE}-${PI_DIRTY_RATIO_VALUE}"
    print_review_item "Allocator tuning" "arena=${RUNTIME_MALLOC_ARENA_MAX_VALUE} trim=${RUNTIME_MALLOC_TRIM_THRESHOLD_VALUE}"
  fi
  print_review_item "Driver repo dir" "${DRIVER_DIR}"
  print_review_item "Env template" "${CHATBOT_ENV_TEMPLATE}"
  print_review_item "Env output" "${CHATBOT_ENV_FILE}"

  if [ "${ENABLE_RAG_VALUE}" = "true" ]; then
    print_review_item "RAG enabled" "yes"
    print_review_item "Serve local Qdrant" "$(format_enabled "${SERVE_QDRANT_VALUE}")"
    print_review_item "Qdrant host" "${QDRANT_HOST_VALUE}"
    print_review_item "Embedding runtime" "${EMBEDDING_RUNTIME_LABEL}"
    print_review_item "Embedding endpoint" "${OLLAMA_EMBEDDING_ENDPOINT_VALUE}"
    print_review_item "Embedding model" "${OLLAMA_EMBEDDING_MODEL_VALUE}"
    if [ "${NATIVE_OLLAMA_FOR_EMBEDDINGS}" = "true" ]; then
      print_review_item "Install native Ollama" "$(format_enabled "${INSTALL_OLLAMA}")"
      print_review_item "Pre-download embedding" "$(format_enabled "${DOWNLOAD_OLLAMA_EMBEDDING_MODEL}")"
    fi
    print_review_item "RAG threshold" "${RAG_KNOWLEDGE_SCORE_THRESHOLD_VALUE}"
    print_review_item "RAG top K" "${RAG_KNOWLEDGE_TOP_K_VALUE}"
    print_review_item "RAG max chunks" "${RAG_KNOWLEDGE_MAX_CHUNKS_VALUE}"
  else
    print_review_item "RAG enabled" "no"
  fi

  if [ "${INSTALL_WAKE_WORD}" = true ]; then
    print_review_item "Wake engine" "${WAKE_WORD_ENGINE}"
    print_review_item "Wake end keywords" "${WAKE_WORD_END_KEYWORDS_VALUE}"
    if [ "${WAKE_WORD_ENGINE}" = "local-wake" ]; then
      print_review_item "Wake phrase" "${WAKE_WORD_PHRASE}"
      print_review_item "Wake sample dir" "${WAKE_WORD_REFERENCE_DIR}"
      print_review_item "Record samples" "$(format_enabled "${RECORD_WAKE_WORD_SAMPLES}")"
    else
      print_review_item "Wake model" "${WAKE_WORD_OPENWAKEWORD_MODEL}"
      print_review_item "Wake cooldown" "${WAKE_WORD_COOLDOWN_SEC}s"
      print_review_item "Pre-download model" "$(format_enabled "${DOWNLOAD_OPENWAKEWORD_MODEL}")"
    fi
  fi
}

reset_install_choices() {
  ASR_LANGUAGE="en"
  ASR_LANGUAGE_LABEL="English"
  ASSISTANT_LANGUAGE_LABEL="English"
  ASSISTANT_SYSTEM_PROMPT="You are a practical voice assistant running on a Raspberry Pi. Reply in English unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess."
  LLM_SERVER_SELECTION="llama.cpp"
  LLM_PROVIDER="llama.cpp"
  SERVE_LLAMA_CPP_VALUE="true"
  SERVE_OLLAMA_VALUE="false"
  SERVE_QDRANT_VALUE="false"
  OLLAMA_ENDPOINT_VALUE="http://192.168.1.100:11434"
  OLLAMA_MODEL_VALUE="gemma3:4b"
  OLLAMA_ENABLE_TOOLS_VALUE="false"
  OLLAMA_API_KEY_VALUE=""
  OPENAI_API_BASE_URL_VALUE="https://api.deepseek.com/v1"
  OPENAI_API_KEY_VALUE=""
  OPENAI_LLM_MODEL_VALUE="deepseek-chat"
  OPENAI_ENABLE_TOOLS_VALUE="false"
  ENABLE_THINKING_VALUE="false"
  USE_CAPTURED_IMAGE_IN_CHAT_VALUE="false"
  LLAMA_CPP_HF_TOKEN_VALUE="${HF_TOKEN:-}"
  ENABLE_RAG_VALUE="false"
  EMBEDDING_SERVER_VALUE="ollama"
  VECTOR_DB_SERVER_VALUE="qdrant"
  EMBEDDING_RUNTIME_LABEL="LAN Ollama endpoint"
  INSTALL_OLLAMA=false
  DOWNLOAD_OLLAMA_EMBEDDING_MODEL=false
  NATIVE_OLLAMA_FOR_EMBEDDINGS=false
  APPLY_PI_MEMORY_TUNING=false
  PI_MEMORY_PROFILE_LABEL="disabled"
  PI_MEMORY_MODE_VALUE="balanced"
  PI_ZRAM_PERCENT_VALUE="50"
  PI_ZRAM_ALGO_VALUE="lz4"
  PI_DISK_SWAP_MB_VALUE="1024"
  PI_SWAPPINESS_VALUE="100"
  PI_VFS_CACHE_PRESSURE_VALUE="150"
  PI_DIRTY_BACKGROUND_RATIO_VALUE="2"
  PI_DIRTY_RATIO_VALUE="10"
  RUNTIME_MALLOC_ARENA_MAX_VALUE="2"
  RUNTIME_MALLOC_TRIM_THRESHOLD_VALUE="131072"
  QDRANT_HOST_VALUE="http://127.0.0.1:6333"
  OLLAMA_EMBEDDING_ENDPOINT_VALUE="http://192.168.1.100:11434"
  OLLAMA_EMBEDDING_MODEL_VALUE="nomic-embed-text"
  RAG_KNOWLEDGE_SCORE_THRESHOLD_VALUE="0.60"
  RAG_KNOWLEDGE_TOP_K_VALUE="5"
  RAG_KNOWLEDGE_MAX_CHUNKS_VALUE="3"
  RAG_KNOWLEDGE_MAX_CHUNKS_PER_SOURCE_VALUE="2"
  RAG_KNOWLEDGE_MAX_CONTEXT_CHARS_VALUE="1800"
  WAKE_WORD_ENGINE="disabled"
  WAKE_WORD_PHRASE=""
  WAKE_WORD_REFERENCE_DIR=""
  WAKE_WORD_THRESHOLD="0.16"
  WAKE_WORD_BUFFER_SIZE="1.8"
  WAKE_WORD_SLIDE_SIZE="0.25"
  WAKE_WORD_SAMPLE_COUNT="4"
  WAKE_WORD_SAMPLE_DURATION="3"
  WAKE_WORD_OPENWAKEWORD_MODEL="hey_jarvis"
  WAKE_WORD_COOLDOWN_SEC="1.5"
  WAKE_WORD_VAD_THRESHOLD="0.2"
  WAKE_WORD_ENABLE_SPEEX="true"
  WAKE_WORD_END_KEYWORDS_VALUE="byebye,goodbye,stop"
  DOWNLOAD_OPENWAKEWORD_MODEL=false
  RECORD_WAKE_WORD_SAMPLES=false
  TTS_SERVER_SELECTION="piper-http"
  TTS_PROFILE_LABEL="Piper HTTP"
  SHERPA_ONNX_TTS_DIR="${DEFAULT_SHERPA_ONNX_TTS_DIR}"
  SHERPA_ONNX_TTS_MODEL_PACKAGE="vits-piper-pl_PL-gosia-medium"
  SHERPA_ONNX_TTS_MODEL_LABEL="Polish: pl_PL-gosia-medium"
  SHERPA_ONNX_TTS_MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-pl_PL-gosia-medium.tar.bz2"
  SHERPA_ONNX_TTS_HOST_VALUE="127.0.0.1"
  SHERPA_ONNX_TTS_PORT_VALUE="8809"
  SHERPA_ONNX_TTS_NUM_THREADS_VALUE="2"
  SHERPA_ONNX_TTS_PROVIDER_VALUE="cpu"
  SHERPA_ONNX_TTS_SPEAKER_ID_VALUE="0"
  SHERPA_ONNX_TTS_SPEED_VALUE="1.0"
  DOWNLOAD_SHERPA_ONNX_TTS_MODEL=true
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

apply_rag_defaults_for_language() {
  if [ "${ASR_LANGUAGE}" = "pl" ]; then
    RAG_KNOWLEDGE_SCORE_THRESHOLD_VALUE="0.55"
    RAG_KNOWLEDGE_TOP_K_VALUE="6"
    RAG_KNOWLEDGE_MAX_CHUNKS_VALUE="4"
    RAG_KNOWLEDGE_MAX_CHUNKS_PER_SOURCE_VALUE="2"
    RAG_KNOWLEDGE_MAX_CONTEXT_CHARS_VALUE="2200"
  else
    RAG_KNOWLEDGE_SCORE_THRESHOLD_VALUE="0.60"
    RAG_KNOWLEDGE_TOP_K_VALUE="5"
    RAG_KNOWLEDGE_MAX_CHUNKS_VALUE="3"
    RAG_KNOWLEDGE_MAX_CHUNKS_PER_SOURCE_VALUE="2"
    RAG_KNOWLEDGE_MAX_CONTEXT_CHARS_VALUE="1800"
  fi
}

pick_rag_config() {
  if ! prompt_yes_no "Enable RAG knowledge retrieval" "n"; then
    ENABLE_RAG_VALUE="false"
    SERVE_QDRANT_VALUE="false"
    EMBEDDING_RUNTIME_LABEL="LAN Ollama endpoint"
    INSTALL_OLLAMA=false
    DOWNLOAD_OLLAMA_EMBEDDING_MODEL=false
    NATIVE_OLLAMA_FOR_EMBEDDINGS=false
    return 0
  fi

  local embedding_choice

  ENABLE_RAG_VALUE="true"
  EMBEDDING_SERVER_VALUE="ollama"
  VECTOR_DB_SERVER_VALUE="qdrant"
  INSTALL_OLLAMA=false
  DOWNLOAD_OLLAMA_EMBEDDING_MODEL=false
  NATIVE_OLLAMA_FOR_EMBEDDINGS=false
  apply_rag_defaults_for_language

  print_section "RAG setup"
  print_note "Recommended setup: keep Qdrant on the Pi and use a small Ollama embedding model on a local or LAN Ollama server."
  print_note "Native Ollama on the Pi is different from Ollama Cloud: it only handles local embeddings here, while your main answer model can stay cloud-based."
  if [ "${ASR_LANGUAGE}" = "pl" ]; then
    print_note "Polish mode: using lower threshold and slightly broader retrieval defaults to better tolerate voice phrasing variation."
  fi

  if prompt_yes_no "Start local Qdrant automatically on this Pi with run_chatbot.sh" "y"; then
    SERVE_QDRANT_VALUE="true"
    QDRANT_HOST_VALUE="http://127.0.0.1:6333"
  else
    SERVE_QDRANT_VALUE="false"
  fi

  if [ "${SERVE_QDRANT_VALUE}" = "false" ]; then
    QDRANT_HOST_VALUE=$(prompt_value "Enter Qdrant host" "${QDRANT_HOST_VALUE}")
  fi

  if [ "${LLM_SERVER_SELECTION}" = "ollama" ]; then
    embedding_choice=$(choose_from_menu \
      "Select the Ollama embedding runtime" \
      "1" \
      "1|Reuse the same LAN Ollama endpoint as the main LLM" \
      "2|Native Ollama on this Pi for embeddings" \
      "3|Different Ollama endpoint")
  else
    embedding_choice=$(choose_from_menu \
      "Select the Ollama embedding runtime" \
      "1" \
      "1|Native Ollama on this Pi for embeddings" \
      "2|Another Ollama endpoint on your LAN or network")
  fi

  case "${embedding_choice}" in
    1)
      if [ "${LLM_SERVER_SELECTION}" = "ollama" ]; then
        EMBEDDING_RUNTIME_LABEL="Reuse main LLM Ollama endpoint"
        OLLAMA_EMBEDDING_ENDPOINT_VALUE="${OLLAMA_ENDPOINT_VALUE}"
      else
        EMBEDDING_RUNTIME_LABEL="Native Ollama on this Pi"
        OLLAMA_EMBEDDING_ENDPOINT_VALUE="http://127.0.0.1:11434"
        NATIVE_OLLAMA_FOR_EMBEDDINGS=true
        SERVE_OLLAMA_VALUE="false"
        if command -v ollama >/dev/null 2>&1; then
          print_note "Existing native Ollama detected on this Pi."
          if prompt_yes_no "Reinstall or refresh native Ollama during setup" "n"; then
            INSTALL_OLLAMA=true
          fi
        else
          print_note "Native Ollama was not found. The installer will add it for local embeddings."
          INSTALL_OLLAMA=true
        fi
      fi
      ;;
    2)
      if [ "${LLM_SERVER_SELECTION}" = "ollama" ]; then
        EMBEDDING_RUNTIME_LABEL="Native Ollama on this Pi"
        OLLAMA_EMBEDDING_ENDPOINT_VALUE="http://127.0.0.1:11434"
        NATIVE_OLLAMA_FOR_EMBEDDINGS=true
        SERVE_OLLAMA_VALUE="false"
        if command -v ollama >/dev/null 2>&1; then
          print_note "Existing native Ollama detected on this Pi."
          if prompt_yes_no "Reinstall or refresh native Ollama during setup" "n"; then
            INSTALL_OLLAMA=true
          fi
        else
          print_note "Native Ollama was not found. The installer will add it for local embeddings."
          INSTALL_OLLAMA=true
        fi
      else
        EMBEDDING_RUNTIME_LABEL="Custom Ollama endpoint"
        OLLAMA_EMBEDDING_ENDPOINT_VALUE=$(prompt_value "Enter Ollama embedding endpoint" "${OLLAMA_EMBEDDING_ENDPOINT_VALUE}")
      fi
      ;;
    3)
      EMBEDDING_RUNTIME_LABEL="Custom Ollama endpoint"
      OLLAMA_EMBEDDING_ENDPOINT_VALUE=$(prompt_value "Enter Ollama embedding endpoint" "${OLLAMA_EMBEDDING_ENDPOINT_VALUE}")
      ;;
    *)
      die "Invalid embedding runtime choice"
      ;;
  esac

  OLLAMA_EMBEDDING_MODEL_VALUE=$(prompt_value "Enter Ollama embedding model" "${OLLAMA_EMBEDDING_MODEL_VALUE}")
  if [ "${NATIVE_OLLAMA_FOR_EMBEDDINGS}" = "true" ]; then
    if prompt_yes_no "Pre-download the Ollama embedding model during install" "y"; then
      DOWNLOAD_OLLAMA_EMBEDDING_MODEL=true
    fi
  fi
  RAG_KNOWLEDGE_SCORE_THRESHOLD_VALUE=$(prompt_value "RAG score threshold" "${RAG_KNOWLEDGE_SCORE_THRESHOLD_VALUE}")
  RAG_KNOWLEDGE_TOP_K_VALUE=$(prompt_value "RAG retrieval top K" "${RAG_KNOWLEDGE_TOP_K_VALUE}")
  RAG_KNOWLEDGE_MAX_CHUNKS_VALUE=$(prompt_value "RAG max chunks in prompt" "${RAG_KNOWLEDGE_MAX_CHUNKS_VALUE}")
  RAG_KNOWLEDGE_MAX_CHUNKS_PER_SOURCE_VALUE=$(prompt_value "RAG max chunks per source" "${RAG_KNOWLEDGE_MAX_CHUNKS_PER_SOURCE_VALUE}")
  RAG_KNOWLEDGE_MAX_CONTEXT_CHARS_VALUE=$(prompt_value "RAG max context characters" "${RAG_KNOWLEDGE_MAX_CONTEXT_CHARS_VALUE}")
}

pick_polish_speed_profile() {
  local choice

  if [ "${ASR_LANGUAGE}" != "pl" ]; then
    return 0
  fi

  choice=$(choose_from_menu \
    "Select the Polish speed and quality profile" \
    "1" \
    "1|Recommended for Pi 5 8GB with smart cloud LLM: base ASR + short history" \
    "2|Higher Polish accuracy: small ASR + shorter history" \
    "3|Keep my manual ASR and history choices")

  case "${choice}" in
    1)
      ASR_MODEL="base"
      BRAIN_MAX_MESSAGES_DEFAULT="6"
      ENABLE_THINKING_VALUE="false"
      USE_CAPTURED_IMAGE_IN_CHAT_VALUE="false"
      ;;
    2)
      ASR_MODEL="small"
      BRAIN_MAX_MESSAGES_DEFAULT="5"
      ENABLE_THINKING_VALUE="false"
      USE_CAPTURED_IMAGE_IN_CHAT_VALUE="false"
      ;;
    3)
      ;;
    *)
      die "Invalid Polish profile choice"
      ;;
  esac

  if [ "${LLM_SERVER_SELECTION}" = "ollama-cloud" ] && [ -z "${OLLAMA_MODEL_VALUE:-}" ]; then
    OLLAMA_MODEL_VALUE="gemma3:27b-cloud"
  fi
}

apply_polish_wake_defaults() {
  WAKE_WORD_END_KEYWORDS_VALUE="koniec,dziekuje,to wszystko,do widzenia,stop"
  if [ "${WAKE_WORD_ENGINE}" = "openwakeword" ]; then
    WAKE_WORD_THRESHOLD="0.55"
    WAKE_WORD_COOLDOWN_SEC="2.0"
    WAKE_WORD_VAD_THRESHOLD="0.25"
    WAKE_WORD_ENABLE_SPEEX="true"
  elif [ "${WAKE_WORD_ENGINE}" = "local-wake" ]; then
    WAKE_WORD_THRESHOLD="0.14"
    WAKE_WORD_BUFFER_SIZE="1.8"
    WAKE_WORD_SLIDE_SIZE="0.25"
  fi
}

download_openwakeword_models() {
  local models_csv="$1"

  if [ -z "${models_csv}" ]; then
    return 0
  fi

  log "Pre-downloading openWakeWord models: ${models_csv}"
  OWW_MODELS="${models_csv}" python3 - <<'PY'
import os

from openwakeword.utils import download_models

models = [item.strip() for item in os.environ.get("OWW_MODELS", "").split(",") if item.strip()]
if not models:
    raise SystemExit(0)

download_models(model_names=models)
PY
}

pick_pi_memory_tuning() {
  local profile_choice

  if ! prompt_yes_no "Apply Raspberry Pi 5 memory tuning for smoother ASR and indexing" "y"; then
    APPLY_PI_MEMORY_TUNING=false
    PI_MEMORY_PROFILE_LABEL="disabled"
    return 0
  fi

  APPLY_PI_MEMORY_TUNING=true
  profile_choice=$(choose_from_menu \
    "Select the Pi memory tuning mode" \
    "1" \
    "1|Balanced: safer everyday tuning for Pi 5 8GB" \
    "2|Aggressive: more compressed memory and larger fallback swap" \
    "3|Custom values")

  case "${profile_choice}" in
    1)
      PI_MEMORY_MODE_VALUE="balanced"
      PI_MEMORY_PROFILE_LABEL="balanced zram + swap"
      PI_ZRAM_PERCENT_VALUE="50"
      PI_ZRAM_ALGO_VALUE="lz4"
      PI_DISK_SWAP_MB_VALUE="1024"
      PI_SWAPPINESS_VALUE="100"
      PI_VFS_CACHE_PRESSURE_VALUE="150"
      PI_DIRTY_BACKGROUND_RATIO_VALUE="2"
      PI_DIRTY_RATIO_VALUE="10"
      RUNTIME_MALLOC_ARENA_MAX_VALUE="2"
      RUNTIME_MALLOC_TRIM_THRESHOLD_VALUE="131072"
      ;;
    2)
      PI_MEMORY_MODE_VALUE="aggressive"
      PI_MEMORY_PROFILE_LABEL="aggressive zram + larger swap"
      PI_ZRAM_PERCENT_VALUE="75"
      PI_ZRAM_ALGO_VALUE="lz4"
      PI_DISK_SWAP_MB_VALUE="2048"
      PI_SWAPPINESS_VALUE="120"
      PI_VFS_CACHE_PRESSURE_VALUE="200"
      PI_DIRTY_BACKGROUND_RATIO_VALUE="1"
      PI_DIRTY_RATIO_VALUE="6"
      RUNTIME_MALLOC_ARENA_MAX_VALUE="2"
      RUNTIME_MALLOC_TRIM_THRESHOLD_VALUE="65536"
      ;;
    3)
      PI_MEMORY_MODE_VALUE="custom"
      PI_MEMORY_PROFILE_LABEL="custom zram + swap"
      ;;
    *) die "Invalid Pi memory tuning mode" ;;
  esac

  if [ "${ASR_LANGUAGE}" = "pl" ]; then
    if [ "${PI_MEMORY_MODE_VALUE}" = "balanced" ]; then
      PI_ZRAM_PERCENT_VALUE="55"
      PI_DISK_SWAP_MB_VALUE="1536"
      PI_SWAPPINESS_VALUE="110"
    elif [ "${PI_MEMORY_MODE_VALUE}" = "aggressive" ]; then
      PI_ZRAM_PERCENT_VALUE="80"
      PI_DISK_SWAP_MB_VALUE="3072"
      PI_SWAPPINESS_VALUE="140"
    fi
  fi

  PI_ZRAM_PERCENT_VALUE=$(prompt_value "ZRAM percent of RAM" "${PI_ZRAM_PERCENT_VALUE}")
  PI_ZRAM_ALGO_VALUE=$(prompt_value "ZRAM compression algorithm" "${PI_ZRAM_ALGO_VALUE}")
  PI_DISK_SWAP_MB_VALUE=$(prompt_value "Disk swap size in MB" "${PI_DISK_SWAP_MB_VALUE}")
  PI_SWAPPINESS_VALUE=$(prompt_value "Linux swappiness" "${PI_SWAPPINESS_VALUE}")
  PI_VFS_CACHE_PRESSURE_VALUE=$(prompt_value "Linux vfs_cache_pressure" "${PI_VFS_CACHE_PRESSURE_VALUE}")
  PI_DIRTY_BACKGROUND_RATIO_VALUE=$(prompt_value "vm.dirty_background_ratio" "${PI_DIRTY_BACKGROUND_RATIO_VALUE}")
  PI_DIRTY_RATIO_VALUE=$(prompt_value "vm.dirty_ratio" "${PI_DIRTY_RATIO_VALUE}")
  RUNTIME_MALLOC_ARENA_MAX_VALUE=$(prompt_value "Runtime MALLOC_ARENA_MAX" "${RUNTIME_MALLOC_ARENA_MAX_VALUE}")
  RUNTIME_MALLOC_TRIM_THRESHOLD_VALUE=$(prompt_value "Runtime MALLOC_TRIM_THRESHOLD_" "${RUNTIME_MALLOC_TRIM_THRESHOLD_VALUE}")
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

  print_section "${title}" >&2
  local entry key label choices=""
  for entry in "$@"; do
    key="${entry%%|*}"
    label="${entry#*|}"
    printf '  %s[%s]%s %s\n' "${COLOR_GREEN}" "${key}" "${COLOR_RESET}" "${label}" >&2
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

download_ollama_embedding_model() {
  local temp_ollama_pid=""
  local attempt

  if ! command -v ollama >/dev/null 2>&1; then
    warn "Skipping Ollama embedding pre-download because the ollama command was not found."
    return 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    warn "Skipping Ollama embedding pre-download because curl is not installed."
    return 1
  fi

  if ! curl -fsS "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
    if command -v systemctl >/dev/null 2>&1 && sudo systemctl list-unit-files ollama.service >/dev/null 2>&1; then
      log "Starting native Ollama systemd service"
      sudo systemctl daemon-reload >/dev/null 2>&1 || true
      sudo systemctl restart ollama >/dev/null 2>&1 || true
      for attempt in $(seq 1 20); do
        if curl -fsS "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done
    fi
  fi

  if ! curl -fsS "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
    log "Starting a temporary local Ollama server for embedding model download"
    OLLAMA_HOST=127.0.0.1:11434 ollama serve >/tmp/whisplay-ollama-install.log 2>&1 &
    temp_ollama_pid=$!
    for attempt in $(seq 1 20); do
      if curl -fsS "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
  fi

  if ! curl -fsS "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
    warn "Skipping Ollama embedding pre-download because the local Ollama API is not reachable on 127.0.0.1:11434."
    if [ -n "${temp_ollama_pid}" ]; then
      kill "${temp_ollama_pid}" >/dev/null 2>&1 || true
      wait "${temp_ollama_pid}" 2>/dev/null || true
    fi
    return 1
  fi

  log "Pre-downloading Ollama embedding model: ${OLLAMA_EMBEDDING_MODEL_VALUE}"
  if ! OLLAMA_HOST=127.0.0.1:11434 ollama pull "${OLLAMA_EMBEDDING_MODEL_VALUE}"; then
    warn "Failed to pre-download Ollama embedding model ${OLLAMA_EMBEDDING_MODEL_VALUE}."
    if [ -n "${temp_ollama_pid}" ]; then
      kill "${temp_ollama_pid}" >/dev/null 2>&1 || true
      wait "${temp_ollama_pid}" 2>/dev/null || true
    fi
    return 1
  fi

  if [ -n "${temp_ollama_pid}" ]; then
    kill "${temp_ollama_pid}" >/dev/null 2>&1 || true
    wait "${temp_ollama_pid}" 2>/dev/null || true
  fi

  return 0
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

set_default_assistant_prompt_for_language() {
  local language_code="$1"

  case "${language_code}" in
    pl)
      ASSISTANT_LANGUAGE_LABEL="Polish"
      ASSISTANT_SYSTEM_PROMPT="You are a practical voice assistant running on a Raspberry Pi. Always reply in Polish unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess."
      ;;
    de)
      ASSISTANT_LANGUAGE_LABEL="German"
      ASSISTANT_SYSTEM_PROMPT="You are a practical voice assistant running on a Raspberry Pi. Always reply in German unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess."
      ;;
    *)
      ASSISTANT_LANGUAGE_LABEL="English"
      ASSISTANT_SYSTEM_PROMPT="You are a practical voice assistant running on a Raspberry Pi. Reply in English unless the user clearly asks for another language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess."
      ;;
  esac
}

pick_assistant_language() {
  local choice custom_label

  choice=$(choose_from_menu \
    "Select the assistant reply language" \
    "1" \
    "1|English" \
    "2|Polish" \
    "3|German" \
    "4|Custom instruction")

  case "${choice}" in
    1)
      set_default_assistant_prompt_for_language "en"
      ;;
    2)
      set_default_assistant_prompt_for_language "pl"
      ;;
    3)
      set_default_assistant_prompt_for_language "de"
      ;;
    4)
      custom_label=$(prompt_value "Enter assistant language label" "Custom")
      ASSISTANT_LANGUAGE_LABEL="${custom_label}"
      ASSISTANT_SYSTEM_PROMPT=$(prompt_value "Enter assistant language instruction" "You are a practical voice assistant running on a Raspberry Pi. Reply in the user's preferred language. Keep answers short, natural, and directly useful for spoken conversation. Prefer clear actions and concrete facts over long explanations. If you are unsure, say so plainly and do not guess.")
      ;;
    *) die "Invalid assistant language choice" ;;
  esac
}

pick_asr_language() {
  local choice custom_code

  choice=$(choose_from_menu \
    "Select the ASR language" \
    "1" \
    "1|English (en)" \
    "2|Polish (pl)" \
    "3|German (de)" \
    "4|Auto detect / empty" \
    "5|Custom language code")

  case "${choice}" in
    1)
      ASR_LANGUAGE="en"
      ASR_LANGUAGE_LABEL="English"
      ;;
    2)
      ASR_LANGUAGE="pl"
      ASR_LANGUAGE_LABEL="Polish"
      ;;
    3)
      ASR_LANGUAGE="de"
      ASR_LANGUAGE_LABEL="German"
      ;;
    4)
      ASR_LANGUAGE=""
      ASR_LANGUAGE_LABEL="Auto detect"
      ;;
    5)
      custom_code=$(prompt_value "Enter faster-whisper language code (for example en, pl, de)" "en")
      ASR_LANGUAGE="${custom_code}"
      ASR_LANGUAGE_LABEL="Custom (${custom_code:-auto})"
      ;;
    *) die "Invalid ASR language choice" ;;
  esac
}

pick_tts_voice() {
  local backend_choice voice_choice

  backend_choice=$(choose_from_menu \
    "Select the local TTS backend" \
    "1" \
    "1|Piper HTTP (recommended, simplest)" \
    "2|Sherpa ONNX (offline comparison option on the Pi)")

  case "${backend_choice}" in
    1)
      TTS_SERVER_SELECTION="piper-http"
      TTS_PROFILE_LABEL="Piper HTTP"
      voice_choice=$(choose_from_menu \
        "Select the Piper voice" \
        "1" \
        "1|English: en_US-lessac-medium (recommended)" \
        "2|Polish: pl_PL-gosia-medium" \
        "3|German: de_DE-thorsten-medium" \
        "4|custom voice id")
      case "${voice_choice}" in
        1)
          PIPER_VOICE="en_US-lessac-medium"
          ;;
        2)
          PIPER_VOICE="pl_PL-gosia-medium"
          ;;
        3)
          PIPER_VOICE="de_DE-thorsten-medium"
          ;;
        4)
          PIPER_VOICE=$(prompt_value "Enter Piper voice id" "en_US-lessac-medium")
          ;;
        *) die "Invalid Piper voice choice" ;;
      esac
      ;;
    2)
      TTS_SERVER_SELECTION="sherpa-onnx"
      TTS_PROFILE_LABEL="Sherpa ONNX"
      voice_choice=$(choose_from_menu \
        "Select the Sherpa ONNX voice" \
        "1" \
        "1|Polish: pl_PL-gosia-medium" \
        "2|Polish: pl_PL-darkman-medium" \
        "3|custom Sherpa ONNX model package")
      case "${voice_choice}" in
        1)
          SHERPA_ONNX_TTS_MODEL_PACKAGE="vits-piper-pl_PL-gosia-medium"
          SHERPA_ONNX_TTS_MODEL_LABEL="Polish: pl_PL-gosia-medium"
          ;;
        2)
          SHERPA_ONNX_TTS_MODEL_PACKAGE="vits-piper-pl_PL-darkman-medium"
          SHERPA_ONNX_TTS_MODEL_LABEL="Polish: pl_PL-darkman-medium"
          ;;
        3)
          SHERPA_ONNX_TTS_MODEL_PACKAGE=$(prompt_value "Enter Sherpa ONNX model package name" "vits-piper-pl_PL-gosia-medium")
          SHERPA_ONNX_TTS_MODEL_LABEL=$(prompt_value "Enter Sherpa ONNX model label" "Custom Sherpa ONNX voice")
          ;;
        *) die "Invalid Sherpa ONNX voice choice" ;;
      esac
      SHERPA_ONNX_TTS_MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${SHERPA_ONNX_TTS_MODEL_PACKAGE}.tar.bz2"
      if prompt_yes_no "Pre-download Sherpa ONNX TTS model during install" "y"; then
        DOWNLOAD_SHERPA_ONNX_TTS_MODEL=true
      else
        DOWNLOAD_SHERPA_ONNX_TTS_MODEL=false
      fi
      ;;
    *) die "Invalid TTS backend choice" ;;
  esac
}

download_sherpa_onnx_tts_model() {
  local url="$1"
  local target_root="$2"
  local package_name="$3"

  if [ -z "${url}" ] || [ -z "${package_name}" ]; then
    warn "Skipping Sherpa ONNX model download because the model URL or package name is empty."
    return 1
  fi

  mkdir -p "${target_root}"
  SHERPA_URL="${url}" SHERPA_TARGET_ROOT="${target_root}" SHERPA_PACKAGE_NAME="${package_name}" python3 - <<'PY'
import bz2
import os
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path

url = os.environ["SHERPA_URL"]
target_root = Path(os.environ["SHERPA_TARGET_ROOT"]).expanduser()
package_name = os.environ["SHERPA_PACKAGE_NAME"]
model_dir = target_root / package_name

if model_dir.exists() and any(model_dir.iterdir()):
    print(f"Sherpa ONNX model already present: {model_dir}")
    raise SystemExit(0)

target_root.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory() as temp_dir:
    archive_path = Path(temp_dir) / f"{package_name}.tar.bz2"
    print(f"Downloading {url} -> {archive_path}")
    urllib.request.urlretrieve(url, archive_path)
    with tarfile.open(archive_path, mode="r:bz2") as tar:
        tar.extractall(path=target_root)

print(f"Sherpa ONNX model ready: {model_dir}")
PY
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
      WAKE_WORD_END_KEYWORDS_VALUE="byebye,goodbye,stop"
      WAKE_WORD_THRESHOLD="0.45"
      WAKE_WORD_COOLDOWN_SEC="1.5"
      WAKE_WORD_VAD_THRESHOLD="0.2"
      WAKE_WORD_ENABLE_SPEEX="true"
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
      if [ "${ASR_LANGUAGE}" = "pl" ]; then
        print_note "Polish profile: using stricter openWakeWord defaults to reduce false triggers with an English preset model."
        apply_polish_wake_defaults
      fi
      WAKE_WORD_THRESHOLD=$(prompt_value "openWakeWord confidence threshold" "${WAKE_WORD_THRESHOLD}")
      WAKE_WORD_COOLDOWN_SEC=$(prompt_value "openWakeWord cooldown in seconds" "${WAKE_WORD_COOLDOWN_SEC}")
      WAKE_WORD_VAD_THRESHOLD=$(prompt_value "openWakeWord VAD threshold" "${WAKE_WORD_VAD_THRESHOLD}")
      if prompt_yes_no "Enable Speex noise suppression for openWakeWord" "y"; then
        WAKE_WORD_ENABLE_SPEEX="true"
      else
        WAKE_WORD_ENABLE_SPEEX="false"
      fi
      if prompt_yes_no "Pre-download the openWakeWord preset model during install for offline first boot" "y"; then
        DOWNLOAD_OPENWAKEWORD_MODEL=true
      fi
      ;;
    2)
      WAKE_WORD_ENGINE="local-wake"
      WAKE_WORD_END_KEYWORDS_VALUE="byebye,goodbye,stop"
      WAKE_WORD_THRESHOLD="0.16"
      WAKE_WORD_BUFFER_SIZE="1.8"
      WAKE_WORD_SLIDE_SIZE="0.25"
      local phrase_choice
      if [ "${ASR_LANGUAGE}" = "pl" ]; then
        apply_polish_wake_defaults
        phrase_choice=$(choose_from_menu \
          "Select the wake phrase label" \
          "1" \
          "1|czesc whisplay" \
          "2|hej asystencie" \
          "3|komputer" \
          "4|custom phrase")
      else
        phrase_choice=$(choose_from_menu \
          "Select the wake phrase label" \
          "1" \
          "1|hey whisplay" \
          "2|hello assistant" \
          "3|computer" \
          "4|custom phrase")
      fi
      case "${phrase_choice}" in
        1)
          if [ "${ASR_LANGUAGE}" = "pl" ]; then
            WAKE_WORD_PHRASE="czesc whisplay"
          else
            WAKE_WORD_PHRASE="hey whisplay"
          fi
          ;;
        2)
          if [ "${ASR_LANGUAGE}" = "pl" ]; then
            WAKE_WORD_PHRASE="hej asystencie"
          else
            WAKE_WORD_PHRASE="hello assistant"
          fi
          ;;
        3)
          if [ "${ASR_LANGUAGE}" = "pl" ]; then
            WAKE_WORD_PHRASE="komputer"
          else
            WAKE_WORD_PHRASE="computer"
          fi
          ;;
        4)
          if [ "${ASR_LANGUAGE}" = "pl" ]; then
            WAKE_WORD_PHRASE=$(prompt_value "Enter custom wake phrase" "czesc whisplay")
          else
            WAKE_WORD_PHRASE=$(prompt_value "Enter custom wake phrase" "hey whisplay")
          fi
          ;;
        *) die "Invalid wake phrase choice" ;;
      esac
      WAKE_WORD_THRESHOLD=$(prompt_value "local-wake distance threshold (lower is stricter)" "${WAKE_WORD_THRESHOLD}")
      WAKE_WORD_BUFFER_SIZE=$(prompt_value "local-wake buffer size (seconds)" "${WAKE_WORD_BUFFER_SIZE}")
      WAKE_WORD_SLIDE_SIZE=$(prompt_value "local-wake slide size (seconds)" "${WAKE_WORD_SLIDE_SIZE}")
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
  if prompt_yes_no "Install local TTS runtime" "y"; then INSTALL_LOCAL_TTS=true; fi
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
  pick_assistant_language
  pick_asr_language
  pick_llm_runtime_mode
  if [ "${LLM_SERVER_SELECTION}" = "llama.cpp" ]; then
    pick_llm_repo
    pick_llama_hf_auth
  fi
  pick_polish_quality_mode
  pick_polish_speed_profile
  pick_rag_config
  pick_pi_memory_tuning
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
  if [ "${TTS_SERVER_SELECTION}" = "piper-http" ]; then
    PIPER_DIR=$(prompt_value "Piper model directory" "${DEFAULT_PIPER_DIR}")
  else
    SHERPA_ONNX_TTS_DIR=$(prompt_value "Sherpa ONNX model directory" "${DEFAULT_SHERPA_ONNX_TTS_DIR}")
  fi

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
set_env_value "${CHATBOT_ENV_FILE}" "TTS_SERVER" "${TTS_SERVER_SELECTION}"
set_env_value "${CHATBOT_ENV_FILE}" "SERVE_LLAMA_CPP" "${SERVE_LLAMA_CPP_VALUE}"
set_env_value "${CHATBOT_ENV_FILE}" "SERVE_OLLAMA" "${SERVE_OLLAMA_VALUE}"
set_env_value "${CHATBOT_ENV_FILE}" "SERVE_QDRANT" "${SERVE_QDRANT_VALUE}"
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
if [ "${TTS_SERVER_SELECTION}" = "piper-http" ]; then
  set_env_value "${CHATBOT_ENV_FILE}" "PIPER_HTTP_HOST" "localhost"
  set_env_value "${CHATBOT_ENV_FILE}" "PIPER_HTTP_PORT" "8805"
  set_env_value "${CHATBOT_ENV_FILE}" "PIPER_HTTP_MODEL" "${PIPER_DIR}/${PIPER_VOICE}"
else
  set_env_value "${CHATBOT_ENV_FILE}" "SHERPA_ONNX_TTS_HOST" "${SHERPA_ONNX_TTS_HOST_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "SHERPA_ONNX_TTS_PORT" "${SHERPA_ONNX_TTS_PORT_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "SHERPA_ONNX_TTS_MODEL_DIR" "${SHERPA_ONNX_TTS_DIR}/${SHERPA_ONNX_TTS_MODEL_PACKAGE}"
  set_env_value "${CHATBOT_ENV_FILE}" "SHERPA_ONNX_TTS_NUM_THREADS" "${SHERPA_ONNX_TTS_NUM_THREADS_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "SHERPA_ONNX_TTS_PROVIDER" "${SHERPA_ONNX_TTS_PROVIDER_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "SHERPA_ONNX_TTS_SPEAKER_ID" "${SHERPA_ONNX_TTS_SPEAKER_ID_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "SHERPA_ONNX_TTS_SPEED" "${SHERPA_ONNX_TTS_SPEED_VALUE}"
fi
set_env_value "${CHATBOT_ENV_FILE}" "SYSTEM_PROMPT" "${ASSISTANT_SYSTEM_PROMPT}"
set_env_value "${CHATBOT_ENV_FILE}" "ENABLE_THINKING" "${ENABLE_THINKING_VALUE}"
set_env_value "${CHATBOT_ENV_FILE}" "USE_CAPTURED_IMAGE_IN_CHAT" "${USE_CAPTURED_IMAGE_IN_CHAT_VALUE}"
if [ "${APPLY_PI_MEMORY_TUNING}" = true ]; then
  set_env_value "${CHATBOT_ENV_FILE}" "MALLOC_ARENA_MAX" "${RUNTIME_MALLOC_ARENA_MAX_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "MALLOC_TRIM_THRESHOLD_" "${RUNTIME_MALLOC_TRIM_THRESHOLD_VALUE}"
fi
set_env_value "${CHATBOT_ENV_FILE}" "ENABLE_RAG" "${ENABLE_RAG_VALUE}"
if [ "${ENABLE_RAG_VALUE}" = "true" ]; then
  set_env_value "${CHATBOT_ENV_FILE}" "EMBEDDING_SERVER" "${EMBEDDING_SERVER_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "VECTOR_DB_SERVER" "${VECTOR_DB_SERVER_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "QDRANT_HOST" "${QDRANT_HOST_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "OLLAMA_EMBEDDING_ENDPOINT" "${OLLAMA_EMBEDDING_ENDPOINT_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "OLLAMA_EMBEDDING_MODEL" "${OLLAMA_EMBEDDING_MODEL_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "RAG_KNOWLEDGE_SCORE_THRESHOLD" "${RAG_KNOWLEDGE_SCORE_THRESHOLD_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "RAG_KNOWLEDGE_TOP_K" "${RAG_KNOWLEDGE_TOP_K_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "RAG_KNOWLEDGE_MAX_CHUNKS" "${RAG_KNOWLEDGE_MAX_CHUNKS_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "RAG_KNOWLEDGE_MAX_CHUNKS_PER_SOURCE" "${RAG_KNOWLEDGE_MAX_CHUNKS_PER_SOURCE_VALUE}"
  set_env_value "${CHATBOT_ENV_FILE}" "RAG_KNOWLEDGE_MAX_CONTEXT_CHARS" "${RAG_KNOWLEDGE_MAX_CONTEXT_CHARS_VALUE}"
fi
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
  set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_END_KEYWORDS" "${WAKE_WORD_END_KEYWORDS_VALUE}"
  if [ "${WAKE_WORD_ENGINE}" = "local-wake" ]; then
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_PHRASE" "${WAKE_WORD_PHRASE}"
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_REFERENCE_DIR" "${WAKE_WORD_REFERENCE_DIR}"
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_LOCAL_WAKE_BUFFER_SIZE" "${WAKE_WORD_BUFFER_SIZE}"
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_LOCAL_WAKE_SLIDE_SIZE" "${WAKE_WORD_SLIDE_SIZE}"
  else
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORDS" "${WAKE_WORD_OPENWAKEWORD_MODEL}"
    set_env_value "${CHATBOT_ENV_FILE}" "WAKE_WORD_COOLDOWN_SEC" "${WAKE_WORD_COOLDOWN_SEC}"
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

chmod +x "${PROJECT_ROOT}/scripts/serve_llama_cpp.sh" "${PROJECT_ROOT}/scripts/install_llama_cpp.sh" "${PROJECT_ROOT}/scripts/install_ollama.sh" "${PROJECT_ROOT}/scripts/optimize_pi_memory.sh" 2>/dev/null || true

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

if [ "${DOWNLOAD_OPENWAKEWORD_MODEL}" = true ] && [ "${WAKE_WORD_ENGINE}" = "openwakeword" ]; then
  if ! download_openwakeword_models "${WAKE_WORD_OPENWAKEWORD_MODEL}"; then
    warn "Skipping openWakeWord model pre-download. Wake word can still work later once the model is downloaded on first run."
  fi
fi

if [ "${DOWNLOAD_ASR_MODEL}" = true ]; then
  download_faster_whisper_model
fi

if [ "${INSTALL_LOCAL_TTS}" = true ]; then
  if [ "${TTS_SERVER_SELECTION}" = "piper-http" ]; then
    log "Installing Piper HTTP dependencies"
    python3 -m pip install --break-system-packages piper-tts==1.3.0 'piper-tts[http]'
    mkdir -p "${PIPER_DIR}"
    (
      cd "${PIPER_DIR}"
      python3 -m piper.download_voices "${PIPER_VOICE}"
    )
  else
    log "Installing Sherpa ONNX TTS dependencies"
    sudo apt-get update
    sudo apt-get install -y libsndfile1
    python3 -m pip install --break-system-packages sherpa-onnx soundfile Flask
    if [ "${DOWNLOAD_SHERPA_ONNX_TTS_MODEL}" = true ]; then
      if ! download_sherpa_onnx_tts_model "${SHERPA_ONNX_TTS_MODEL_URL}" "${SHERPA_ONNX_TTS_DIR}" "${SHERPA_ONNX_TTS_MODEL_PACKAGE}"; then
        warn "Skipping Sherpa ONNX TTS model pre-download. You can download it later by rerunning the installer or extracting the model into ${SHERPA_ONNX_TTS_DIR}."
      fi
    fi
  fi
fi

if [ "${APPLY_PI_MEMORY_TUNING}" = true ]; then
  log "Applying Raspberry Pi memory tuning"
  ZRAM_PERCENT="${PI_ZRAM_PERCENT_VALUE}" \
    ZRAM_ALGO="${PI_ZRAM_ALGO_VALUE}" \
    DISK_SWAP_MB="${PI_DISK_SWAP_MB_VALUE}" \
    SWAPPINESS="${PI_SWAPPINESS_VALUE}" \
    VFS_CACHE_PRESSURE="${PI_VFS_CACHE_PRESSURE_VALUE}" \
    DIRTY_BACKGROUND_RATIO="${PI_DIRTY_BACKGROUND_RATIO_VALUE}" \
    DIRTY_RATIO="${PI_DIRTY_RATIO_VALUE}" \
    RUNTIME_MALLOC_ARENA_MAX="${RUNTIME_MALLOC_ARENA_MAX_VALUE}" \
    RUNTIME_MALLOC_TRIM_THRESHOLD="${RUNTIME_MALLOC_TRIM_THRESHOLD_VALUE}" \
    bash "${PROJECT_ROOT}/scripts/optimize_pi_memory.sh"
fi

if [ "${INSTALL_OLLAMA}" = true ]; then
  log "Installing native Ollama for local embeddings"
  bash "${PROJECT_ROOT}/scripts/install_ollama.sh"
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

if [ "${DOWNLOAD_OLLAMA_EMBEDDING_MODEL}" = true ]; then
  if ! download_ollama_embedding_model; then
    warn "Skipping Ollama embedding model pre-download. RAG can still work after install once you run: ollama pull ${OLLAMA_EMBEDDING_MODEL_VALUE}"
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
