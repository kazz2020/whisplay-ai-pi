#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
REPO_DIR="${LLAMA_CPP_REPO_DIR:-${PROJECT_ROOT}/../llama.cpp-master}"
BUILD_DIR="${LLAMA_CPP_BUILD_DIR:-${REPO_DIR}/build}"
ENABLE_VULKAN="${LLAMA_CPP_ENABLE_VULKAN:-false}"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-dir)
      REPO_DIR="$2"
      shift 2
      ;;
    --build-dir)
      BUILD_DIR="$2"
      shift 2
      ;;
    --enable-vulkan)
      ENABLE_VULKAN=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

log() {
  echo "[install_llama_cpp] $*"
}

die() {
  echo "[install_llama_cpp] $*" >&2
  exit 1
}

if ! command -v git >/dev/null 2>&1; then
  die "git is required"
fi

log "Installing build dependencies"
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  cmake \
  ninja-build \
  pkg-config \
  libssl-dev \
  libcurl4-openssl-dev \
  libopenblas-dev

if [ ! -d "${REPO_DIR}" ]; then
  log "Cloning llama.cpp into ${REPO_DIR}"
  git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "${REPO_DIR}"
fi

cmake_args=(
  -S "${REPO_DIR}"
  -B "${BUILD_DIR}"
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DGGML_NATIVE=ON
  -DGGML_CURL=ON
  -DLLAMA_OPENSSL=ON
  -DLLAMA_BUILD_SERVER=ON
  -DLLAMA_BUILD_TESTS=OFF
  -DLLAMA_BUILD_EXAMPLES=OFF
)

if [ "${ENABLE_VULKAN}" = "true" ]; then
  cmake_args+=( -DGGML_VULKAN=ON )
fi

log "Configuring llama.cpp"
cmake "${cmake_args[@]}"

log "Building llama-server and llama-cli"
cmake --build "${BUILD_DIR}" --config Release --target llama-server llama-cli -j "$(nproc)"

log "Installing llama.cpp runtime and binaries"
sudo cmake --install "${BUILD_DIR}" --prefix /usr/local

if command -v ldconfig >/dev/null 2>&1; then
  log "Refreshing shared library cache"
  sudo ldconfig
fi

log "llama.cpp install complete"
log "Binary: /usr/local/bin/llama-server"
