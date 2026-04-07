#!/bin/bash

debug_mode=false
trace_mode=false

print_usage() {
  cat <<'EOF'
Usage: bash run_chatbot.sh [--debug] [--help]

  --debug   Run in foreground with labeled live output for troubleshooting.
  --trace   Enable verbose button/audio/display event tracing in foreground.
  --help    Show this help text.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)
      debug_mode=true
      ;;
    --trace)
      debug_mode=true
      trace_mode=true
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
  shift
done

prefix_output() {
  local prefix="$1"
  sed -u "s/^/[$prefix] /"
}

start_bg_command() {
  local name="$1"
  shift

  if [ "$debug_mode" = true ]; then
    "$@" > >(prefix_output "$name") 2> >(prefix_output "$name" >&2) &
  else
    "$@" &
  fi
}

run_fg_command() {
  local name="$1"
  shift

  if [ "$debug_mode" = true ]; then
    "$@" > >(prefix_output "$name") 2> >(prefix_output "$name" >&2)
  else
    "$@"
  fi
}

# Set working directory and environment
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
os_name=$(uname -s 2>/dev/null || echo "unknown")
is_linux=false
is_darwin=false
is_windows=false
case "$os_name" in
  Linux*) is_linux=true ;;
  Darwin*) is_darwin=true ;;
  MINGW*|MSYS*|CYGWIN*) is_windows=true ;;
esac

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

if [ "$debug_mode" = true ]; then
  export WHISPLAY_DEBUG=true
  export PYTHONUNBUFFERED=1
  export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--trace-warnings"
fi

if [ "$trace_mode" = true ]; then
  export WHISPLAY_TRACE_EVENTS=true
fi

# Find the sound card index for wm8960soundcard (Linux only)
card_index=""
audio_supported=false
if [ "$is_linux" = true ] && [ -r "/proc/asound/cards" ] && command -v amixer >/dev/null 2>&1; then
  card_index=$(awk '/wm8960soundcard/ {print $1}' /proc/asound/cards | head -n1)
  # Default to 1 if not found
  if [ -z "$card_index" ]; then
    card_index=1
  fi
  audio_supported=true
  echo "Using sound card index: $card_index"
else
  echo "Audio setup skipped for OS: $os_name"
fi

# Output current environment information (for debugging)
echo "===== Start time: $(date) =====" 
echo "Current user: $(whoami)" 
echo "Working directory: $script_dir" 
working_dir="$script_dir"
echo "PATH: $PATH" 
if command -v python3 >/dev/null 2>&1; then
  echo "Python version: $(python3 --version)"
else
  echo "Python version: not found"
fi
if command -v node >/dev/null 2>&1; then
  echo "Node version: $(node --version)"
else
  echo "Node version: not found"
fi
if [ "$debug_mode" = true ]; then
  echo "Debug mode: enabled"
  if [ "$trace_mode" = true ]; then
    echo "Trace mode: enabled"
  fi
  echo "Tip: press Ctrl+C to stop all foreground output."
else
  sleep 5
fi

# Start the service
echo "Starting Node.js application..."
cd $working_dir

get_env_value() {
  if grep -Eq "^[[:space:]]*$1[[:space:]]*=" .env; then
    val=$(grep -E "^[[:space:]]*$1[[:space:]]*=" .env | tail -n1 | cut -d'=' -f2-)
    # trim whitespace and surrounding quotes
    echo "$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
  else
    echo ""
  fi
}

# load .env variables, exclude comments and empty lines
# check if .env file exists
initial_volume_level=114
serve_ollama=false
serve_llama_cpp=false
serve_qdrant=false
llama_cpp_pid=""
qdrant_started=false
if [ -f ".env" ]; then
  # Load only SERVE_OLLAMA from .env (ignore comments/other vars)
  SERVE_OLLAMA=$(get_env_value "SERVE_OLLAMA")
  [ -n "$SERVE_OLLAMA" ] && export SERVE_OLLAMA
  SERVE_LLAMA_CPP=$(get_env_value "SERVE_LLAMA_CPP")
  [ -n "$SERVE_LLAMA_CPP" ] && export SERVE_LLAMA_CPP
  SERVE_QDRANT=$(get_env_value "SERVE_QDRANT")
  [ -n "$SERVE_QDRANT" ] && export SERVE_QDRANT
  
  CUSTOM_FONT_PATH=$(get_env_value "CUSTOM_FONT_PATH")
  [ -n "$CUSTOM_FONT_PATH" ] && export CUSTOM_FONT_PATH

  INITIAL_VOLUME_LEVEL=$(get_env_value "INITIAL_VOLUME_LEVEL")
  [ -n "$INITIAL_VOLUME_LEVEL" ] && export INITIAL_VOLUME_LEVEL

  WHISPER_MODEL_SIZE=$(get_env_value "WHISPER_MODEL_SIZE")
  [ -n "$WHISPER_MODEL_SIZE" ] && export WHISPER_MODEL_SIZE

  FASTER_WHISPER_MODEL_SIZE=$(get_env_value "FASTER_WHISPER_MODEL_SIZE")
  [ -n "$FASTER_WHISPER_MODEL_SIZE" ] && export FASTER_WHISPER_MODEL_SIZE

  MALLOC_ARENA_MAX=$(get_env_value "MALLOC_ARENA_MAX")
  [ -n "$MALLOC_ARENA_MAX" ] && export MALLOC_ARENA_MAX

  MALLOC_TRIM_THRESHOLD_=$(get_env_value "MALLOC_TRIM_THRESHOLD_")
  [ -n "$MALLOC_TRIM_THRESHOLD_" ] && export MALLOC_TRIM_THRESHOLD_

  echo ".env variables loaded."

  # check if SERVE_OLLAMA is set to true
  if [ "$SERVE_OLLAMA" = "true" ]; then
    serve_ollama=true
  fi

  if [ "$SERVE_LLAMA_CPP" = "true" ]; then
    serve_llama_cpp=true
  fi

  if [ "$SERVE_QDRANT" = "true" ]; then
    serve_qdrant=true
  fi

  if [ -n "$INITIAL_VOLUME_LEVEL" ]; then
    initial_volume_level=$INITIAL_VOLUME_LEVEL
  fi
else
  echo ".env file not found, please create one based on .env.template."
  exit 1
fi

: "${MALLOC_ARENA_MAX:=2}"
: "${MALLOC_TRIM_THRESHOLD_:=131072}"
export MALLOC_ARENA_MAX
export MALLOC_TRIM_THRESHOLD_

# Adjust initial volume (Linux only)
if [ "$audio_supported" = true ]; then
  amixer -c $card_index set Speaker $initial_volume_level
fi

if [ "$serve_ollama" = true ]; then
  echo "Starting Ollama server..."
  export OLLAMA_KEEP_ALIVE=-1 # ensure Ollama server stays alive
  start_bg_command "ollama" env OLLAMA_HOST=0.0.0.0:11434 ollama serve
fi

if [ "$serve_llama_cpp" = true ]; then
  echo "Starting llama.cpp server..."
  start_bg_command "llama.cpp" bash "$script_dir/scripts/serve_llama_cpp.sh"
  llama_cpp_pid=$!
fi

run_docker_compose_service() {
  local action="$1"
  local service="$2"
  local compose_file="$script_dir/docker/docker-compose.yml"

  if [ ! -f "$compose_file" ]; then
    echo "Docker compose file not found: $compose_file" >&2
    return 1
  fi

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose -f "$compose_file" "$action" -d "$service"
    return $?
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "$compose_file" "$action" -d "$service"
    return $?
  fi

  echo "Docker Compose not found. Install docker with the compose plugin or docker-compose." >&2
  return 1
}

stop_docker_compose_service() {
  local service="$1"
  local compose_file="$script_dir/docker/docker-compose.yml"

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose -f "$compose_file" stop "$service"
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "$compose_file" stop "$service"
    return 0
  fi

  return 0
}

if [ "$serve_qdrant" = true ]; then
  echo "Starting Qdrant service..."
  if run_docker_compose_service up qdrant; then
    qdrant_started=true
  else
    echo "WARNING: failed to start Qdrant automatically. RAG may not work until Qdrant is running." >&2
  fi
fi

# if file use_npm exists and is true, use npm
if [ -f "use_npm" ]; then
  use_npm=true
else
  use_npm=false
fi

if [ "$use_npm" = true ]; then
  echo "Using npm to start the application..."
  if [ -n "$card_index" ]; then
    run_fg_command "app" env SOUND_CARD_INDEX=$card_index npm start
  else
    run_fg_command "app" npm start
  fi
else
  echo "Using yarn to start the application..."
  if [ -n "$card_index" ]; then
    run_fg_command "app" env SOUND_CARD_INDEX=$card_index yarn start
  else
    run_fg_command "app" yarn start
  fi
fi

# After the service ends, perform cleanup
echo "Cleaning up after service..."

if [ "$serve_ollama" = true ]; then
  echo "Stopping Ollama server..."
  if command -v pkill >/dev/null 2>&1; then
    pkill ollama
  else
    echo "pkill not available; please stop ollama manually if needed."
  fi
fi

if [ -n "$llama_cpp_pid" ] && kill -0 "$llama_cpp_pid" >/dev/null 2>&1; then
  echo "Stopping llama.cpp server..."
  kill "$llama_cpp_pid" >/dev/null 2>&1 || true
fi

if [ "$qdrant_started" = true ]; then
  echo "Stopping Qdrant service..."
  stop_docker_compose_service qdrant >/dev/null 2>&1 || true
fi

# Record end status
echo "===== Service ended: $(date) ====="
