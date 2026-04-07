# Raspberry Pi 5 8GB Assistant

This repo now supports both a fully local Raspberry Pi 5 setup and a Pi-hosted assistant with Ollama Cloud for the LLM:

- Whisplay HAT drivers from PiSugar Whisplay
- Local ASR with faster-whisper
- Local LLM with llama.cpp `llama-server` or remote LLM with Ollama Cloud
- Local TTS with Piper HTTP
- Optional RAG using Qdrant plus Ollama embeddings
- Image generation disabled by default so the preset stays fully local
- Optional systemd startup via the existing chatbot service

## Recommended defaults

For a Pi 5 8GB, start with:

- Brain profile: `Balanced`
- LLM: `bartowski/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M`
- ASR: `tiny` faster-whisper model
- TTS voice: `en_US-lessac-medium`
- Context size: `2048`

These defaults are encoded in `.env.pi5-local.template`.

If you want a Polish-first local setup, start from `.env.pi5-local-pl.template`. That preset switches to:

- `FASTER_WHISPER_MODEL_SIZE_OR_PATH=small`
- `FASTER_WHISPER_LANGUAGE=pl`
- `LLAMA_CPP_HF_REPO=bartowski/gemma-2-2b-it-GGUF:Q4_K_M`
- `PIPER_HTTP_MODEL=/home/pi/piper/pl_PL-gosia-medium`
- a Polish reply `SYSTEM_PROMPT`

For a better free no-key Polish setup, the installer now offers:

- `Pi-only stronger local mode`: local faster-whisper `small` plus local llama.cpp `Gemma 2 2B`
- `LAN Ollama mode`: local faster-whisper on the Pi plus a stronger Ollama model running on another computer in your home network

The installer now offers these Pi-oriented brain profiles:

- `Fast`: Qwen2.5 0.5B, tuned for maximum responsiveness
- `Balanced`: Qwen2.5 1.5B, best default on Pi 5 8GB
- `Higher quality`: Gemma 2 2B, slower but a bit stronger
- `Custom`: manual Hugging Face GGUF repo entry
- `Ollama Cloud`: `gemma3:27b-cloud`, prompts for `OLLAMA_API_KEY`

When you choose a brain profile, the installer also writes matching defaults for threads, context size, batch size, ubatch size, and chat history length into `.env`.

<<<<<<< HEAD
The installer also now lets you choose the LLM runtime mode:

- `Local llama.cpp on the Pi`: fully offline
- `Ollama on another computer in your LAN`: free and no API key, but needs another machine
- `DeepSeek API via OpenAI-compatible endpoint`: online mode for users who already have a DeepSeek key
=======
When you choose `Ollama Cloud`, the installer instead writes `LLM_SERVER=ollama-cloud`, `OLLAMA_ENDPOINT`, `OLLAMA_MODEL`, and `OLLAMA_API_KEY` into `.env`, and skips local llama.cpp setup.
>>>>>>> 9d61f47 (ollama cloud added)

The voice selection also sets matching local-language defaults:

- English voice -> `FASTER_WHISPER_LANGUAGE=en` and English reply prompt
- Polish voice -> `FASTER_WHISPER_LANGUAGE=pl` and Polish reply prompt
- German voice -> `FASTER_WHISPER_LANGUAGE=de` and German reply prompt

## Recommended RAG setup

For Raspberry Pi, the best current RAG setup in this repository is:

- Qdrant for vector storage
- Ollama embeddings with `nomic-embed-text`
- native Ollama on the Pi or a LAN Ollama embedding endpoint
- keep the main assistant model separate from the embedding model

If you choose RAG in the installer, it will ask for:

- `QDRANT_HOST`
- whether embeddings should use native Ollama on the Pi or another Ollama endpoint
- `OLLAMA_EMBEDDING_ENDPOINT`
- `OLLAMA_EMBEDDING_MODEL`
- retrieval tuning values such as threshold and top K

When you choose native Ollama on the Pi, the installer can also install Ollama and pre-pull the embedding model so RAG is ready without any separate LAN machine.

## Recommended Polish cloud setup on Pi 5 8GB

If your priority is good Polish recognition plus a smarter remote model, the recommended setup in this repo is:

- `FASTER_WHISPER_LANGUAGE=pl`
- `FASTER_WHISPER_MODEL_SIZE_OR_PATH=base` for better speed or `small` for better recognition quality
- `LLM_SERVER=ollama-cloud`
- `OLLAMA_MODEL=gemma3:27b-cloud`
- `ENABLE_THINKING=false`
- `USE_CAPTURED_IMAGE_IN_CHAT=false`

The installer now has a Polish speed profile for this and can also apply Pi memory tuning with zram and a modest disk swap fallback. This is useful for smoother ASR, indexing, and package builds on an 8GB Raspberry Pi 5.

After install, add your knowledge files to the repository `knowledge/` directory and run:

```bash
bash index_knowledge.sh
```

## Fresh Pi OS install

Run the interactive installer from the chatbot repository root:

```bash
bash pi5-universal-installer.sh
```

The installer can:

- clone the Whisplay driver repo if missing
- clone/build llama.cpp if missing
- install the WM8960 driver for the Whisplay HAT
- install chatbot dependencies
- install local faster-whisper and Piper dependencies
- install wake word detection with either local-wake or openWakeWord
- pre-download the selected local ASR and LLM models
- generate a local `.env`
- build the chatbot
- install the systemd service

## Wake word options

For Raspberry Pi, choose based on what you want more:

- `openWakeWord` if you want a ready-made English wake word that is more likely to work immediately. The recommended preset is `hey_jarvis`.
- `local-wake` if you want to choose your own phrase. It works by comparing live audio against a small set of reference recordings that you record on the Pi itself.

The installer now offers:

- `openWakeWord`: recommended for an immediate English preset such as `hey_jarvis`
- `local-wake`: recommended only when you specifically need a custom phrase or non-English phrase

If you choose `local-wake`, the installer can immediately record 3 to 5 reference samples and will write matching settings such as:

- `WAKE_WORD_ENABLED=true`
- `WAKE_WORD_ENGINE=local-wake`
- `WAKE_WORD_PHRASE=...`
- `WAKE_WORD_REFERENCE_DIR=...`
- `WAKE_WORD_THRESHOLD=0.12`

You can re-record the samples later with:

```bash
bash scripts/setup_local_wakeword.sh
```

If you hear false activations, lower the threshold slightly. If the wake phrase is missed too often, raise it slightly or re-record cleaner samples.

## Manual llama.cpp setup

If you only want to build the local LLM runtime:

```bash
bash scripts/install_llama_cpp.sh
```

This build enables HTTPS support for Hugging Face downloads. If `llama-server` says HTTPS is not supported, rebuild it with this script and then retry.

To run the local server using your `.env` settings:

```bash
bash scripts/serve_llama_cpp.sh
```

## Notes

- `SERVE_LLAMA_CPP=true` makes `run_chatbot.sh` start `llama-server` automatically.
- Set either `LLAMA_CPP_MODEL_PATH` or `LLAMA_CPP_HF_REPO` in `.env`.
- `LLAMA_CPP_HF_REPO` is the easiest path on a fresh system because `llama-server` can fetch the GGUF model itself.
- If Hugging Face returns `401`, set `LLAMA_CPP_HF_TOKEN=hf_...` in `.env` and retry. `scripts/serve_llama_cpp.sh` will pass it through as `--hf-token`.
- The first launch can take several minutes while the model downloads and warms up.
