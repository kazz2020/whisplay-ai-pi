#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

if [ -f "${PROJECT_ROOT}/.env" ]; then
  set -a
  . "${PROJECT_ROOT}/.env"
  set +a
fi

LLAMA_CPP_HOST="${LLAMA_CPP_HOST:-127.0.0.1}"
LLAMA_CPP_PORT="${LLAMA_CPP_PORT:-8080}"
LLAMA_CPP_ALIAS="${LLAMA_CPP_ALIAS:-${LLAMA_CPP_MODEL:-qwen2.5-1.5b-instruct}}"
LLAMA_CPP_THREADS="${LLAMA_CPP_THREADS:-4}"
LLAMA_CPP_CONTEXT_SIZE="${LLAMA_CPP_CONTEXT_SIZE:-2048}"
LLAMA_CPP_BATCH_SIZE="${LLAMA_CPP_BATCH_SIZE:-256}"
LLAMA_CPP_UBATCH_SIZE="${LLAMA_CPP_UBATCH_SIZE:-128}"
LLAMA_CPP_N_GPU_LAYERS="${LLAMA_CPP_N_GPU_LAYERS:-0}"
LLAMA_CPP_FLASH_ATTN="${LLAMA_CPP_FLASH_ATTN:-off}"
LLAMA_CPP_JINJA="${LLAMA_CPP_JINJA:-true}"
LLAMA_CPP_REASONING="${LLAMA_CPP_REASONING:-off}"
LLAMA_CPP_EXTRA_ARGS="${LLAMA_CPP_EXTRA_ARGS:-}"
LLAMA_CPP_ENABLE_TOOLS="${LLAMA_CPP_ENABLE_TOOLS:-true}"
LLAMA_CPP_HF_TOKEN="${LLAMA_CPP_HF_TOKEN:-${HF_TOKEN:-}}"

log() {
  echo "[llama.cpp] $*"
}

die() {
  echo "[llama.cpp] $*" >&2
  exit 1
}

find_server_bin() {
  local candidates=()
  if [ -n "${LLAMA_CPP_SERVER_BIN:-}" ]; then
    candidates+=("${LLAMA_CPP_SERVER_BIN}")
  fi
  if command -v llama-server >/dev/null 2>&1; then
    candidates+=("$(command -v llama-server)")
  fi
  candidates+=(
    "${PROJECT_ROOT}/../llama.cpp-master/build/bin/llama-server"
    "${PROJECT_ROOT}/../llama.cpp/build/bin/llama-server"
    "${PROJECT_ROOT}/llama.cpp-master/build/bin/llama-server"
    "${PROJECT_ROOT}/llama.cpp/build/bin/llama-server"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

SERVER_BIN=$(find_server_bin) || die "Unable to locate llama-server. Set LLAMA_CPP_SERVER_BIN or run scripts/install_llama_cpp.sh first."

cmd=(
  "${SERVER_BIN}"
  "--host" "${LLAMA_CPP_HOST}"
  "--port" "${LLAMA_CPP_PORT}"
  "-t" "${LLAMA_CPP_THREADS}"
  "-c" "${LLAMA_CPP_CONTEXT_SIZE}"
  "-b" "${LLAMA_CPP_BATCH_SIZE}"
  "-ub" "${LLAMA_CPP_UBATCH_SIZE}"
  "-ngl" "${LLAMA_CPP_N_GPU_LAYERS}"
  "--flash-attn" "${LLAMA_CPP_FLASH_ATTN}"
  "--reasoning" "${LLAMA_CPP_REASONING}"
  "-a" "${LLAMA_CPP_ALIAS}"
  "--no-webui"
)

if [ "${LLAMA_CPP_JINJA}" = "true" ] || [ "${LLAMA_CPP_ENABLE_TOOLS}" = "true" ]; then
  cmd+=("--jinja")
fi

if [ -n "${LLAMA_CPP_API_KEY:-}" ]; then
  cmd+=("--api-key" "${LLAMA_CPP_API_KEY}")
fi

if [ -n "${LLAMA_CPP_HF_TOKEN}" ]; then
  cmd+=("--hf-token" "${LLAMA_CPP_HF_TOKEN}")
fi

if [ -n "${LLAMA_CPP_MODEL_PATH:-}" ]; then
  cmd+=("-m" "${LLAMA_CPP_MODEL_PATH}")
elif [ -n "${LLAMA_CPP_HF_REPO:-}" ]; then
  cmd+=("-hf" "${LLAMA_CPP_HF_REPO}")
else
  die "Set LLAMA_CPP_MODEL_PATH or LLAMA_CPP_HF_REPO in .env before enabling SERVE_LLAMA_CPP."
fi

if [ -n "${LLAMA_CPP_EXTRA_ARGS}" ]; then
  read -r -a extra_args <<< "${LLAMA_CPP_EXTRA_ARGS}"
  cmd+=("${extra_args[@]}")
fi

log "Starting ${SERVER_BIN} on ${LLAMA_CPP_HOST}:${LLAMA_CPP_PORT}"
if [ -n "${LLAMA_CPP_HF_REPO:-}" ]; then
  log "Model source: Hugging Face repo ${LLAMA_CPP_HF_REPO}"
  if [ -n "${LLAMA_CPP_HF_TOKEN}" ]; then
    log "Using Hugging Face token authentication"
  fi
fi
exec "${cmd[@]}"
