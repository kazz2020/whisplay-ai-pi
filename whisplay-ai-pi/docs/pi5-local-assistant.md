# Raspberry Pi 5 8GB Assistant

This repo now supports both a fully local Raspberry Pi 5 setup and a Pi-hosted assistant with Ollama Cloud for the LLM:

- Whisplay HAT drivers from PiSugar Whisplay
- Local ASR with faster-whisper
- Local LLM with llama.cpp `llama-server`, LiteRT-LM, or remote LLM with Ollama Cloud
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
- `LiteRT-LM`: LiteRT local model path using `.litertlm` models such as Gemma 3n or Gemma 4 E2B
- `Ollama Cloud`: `gemma3:27b-cloud`, prompts for `OLLAMA_API_KEY`

When you choose a brain profile, the installer also writes matching defaults for threads, context size, batch size, ubatch size, and chat history length into `.env`.

The installer also now lets you choose the LLM runtime mode:

- `Local llama.cpp on the Pi`: fully offline GGUF path
- `Local LiteRT-LM on the Pi`: fully offline `.litertlm` path
- `Ollama on another computer in your LAN`: free and no API key, but needs another machine
- `DeepSeek API via OpenAI-compatible endpoint`: online mode for users who already have a DeepSeek key

When you choose `Ollama Cloud`, the installer instead writes `LLM_SERVER=ollama-cloud`, `OLLAMA_ENDPOINT`, `OLLAMA_MODEL`, and `OLLAMA_API_KEY` into `.env`, and skips local llama.cpp setup.

If you want to change the cloud model later without rerunning the full installer, run:

```bash
bash switch_ollama_model.sh
```

This updates `OLLAMA_MODEL` in `.env` and optionally restarts `chatbot.service`.

When you choose `LiteRT-LM`, the installer writes `LLM_SERVER=litert-lm` plus `LITERT_LM_MODEL_PATH`, `LITERT_LM_MODEL_REPO`, `LITERT_LM_BACKEND`, and related settings into `.env`.

The initial LiteRT-LM presets are:

- `Gemma 3n E2B LiteRT-LM`: speed-first local option
- `Gemma 4 E2B LiteRT-LM`: balanced local option
- `Custom LiteRT-LM repo`: manual Hugging Face repo entry for `.litertlm` models

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
- install local faster-whisper and local TTS dependencies
- install wake word detection with either local-wake or openWakeWord
- pre-download the selected local ASR and LLM models
- generate a local `.env`
- build the chatbot
- install the systemd service

## Local TTS backend choice

The installer now supports two local TTS backends on Raspberry Pi:

- `piper-http`: the original and most integrated path in this repository
- `sherpa-onnx`: an alternative offline backend so you can compare Polish voices on the same Pi

For Sherpa ONNX, the current installer exposes Polish presets such as `pl_PL-gosia-medium` and `pl_PL-darkman-medium` and downloads the model into a local directory such as `/home/pi/sherpa-onnx-tts/`.

You can switch later by rerunning the installer and picking a different TTS backend, or by updating `TTS_SERVER` and the corresponding TTS environment variables in `.env`.

## Wake word options

For Raspberry Pi, choose based on what you want more:

- `openWakeWord` if you want a ready-made English wake word that is more likely to work immediately. The recommended preset is `hey_jarvis`.
- `local-wake` if you want to choose your own phrase. It works by comparing live audio against a small set of reference recordings that you record on the Pi itself.

The installer now offers:

- `openWakeWord`: recommended for an immediate English preset such as `hey_jarvis`
- `local-wake`: recommended only when you specifically need a custom phrase or non-English phrase

For Polish, `local-wake` is the better default. The installer now offers Polish phrase labels, a slightly stricter local-wake threshold, and Polish end keywords such as `koniec`, `dziekuje`, `to wszystko`, and `do widzenia`.

If you still choose `openWakeWord`, the installer can pre-download the preset model during setup so the first boot can stay offline.

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
