#!/bin/bash
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org}"

# if file use_npm exists and is true, use npm
if [ -f "use_npm" ]; then
  use_npm=true
else
  use_npm=false
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

load_node_env() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
  fi
  if [ -s "$NVM_DIR/bash_completion" ]; then
    . "$NVM_DIR/bash_completion"
  fi
}

# check if .env file exists
if [ ! -f .env ]; then
    echo "Please create a .env file with the necessary environment variables. Please refer to .env.template for guidance."
    exit 1
fi

load_node_env

if [ -f ~/.bashrc ]; then
  . ~/.bashrc || true
fi

if ! command_exists node || ! command_exists npm; then
  echo "Error: node/npm not found in this shell. Run install_dependencies.sh first, then rerun build.sh."
  exit 1
fi

if [ "$use_npm" = true ]; then
  echo "Using npm to build the project."
  npm install --registry=$NPM_REGISTRY
  npm run build
else
  if ! command -v yarn >/dev/null 2>&1; then
    echo "WARNING: yarn not found. Falling back to npm."
    use_npm=true
  fi

  if [ "$use_npm" = true ]; then
    echo "Using npm to build the project."
    npm install --registry=$NPM_REGISTRY
    npm run build
  else
    echo "Using yarn to build the project."
    if ! yarn --registry=$NPM_REGISTRY || ! yarn build; then
      echo "WARNING: yarn failed. Falling back to npm."
      npm install --registry=$NPM_REGISTRY
      npm run build
    fi
  fi
fi