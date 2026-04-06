# Raspberry Pi 5 8GB Local Assistant

This repo now supports a fully local Raspberry Pi 5 setup for the Whisplay HAT:

- Whisplay HAT drivers from PiSugar Whisplay
- Local ASR with faster-whisper
- Local LLM with llama.cpp `llama-server`
- Local TTS with Piper HTTP
- Image generation disabled by default so the preset stays fully local
- Optional systemd startup via the existing chatbot service

## Recommended defaults

For a Pi 5 8GB, start with:

- Brain profile: `Balanced`
- LLM: `ggml-org/Qwen2.5-1.5B-Instruct-GGUF:Q4_K_M`
- ASR: `tiny` faster-whisper model
- TTS voice: `en_US-lessac-medium`
- Context size: `2048`

These defaults are encoded in `.env.pi5-local.template`.

The installer now offers these Pi-oriented brain profiles:

- `Fast`: Qwen2.5 0.5B, tuned for maximum responsiveness
- `Balanced`: Qwen2.5 1.5B, best default on Pi 5 8GB
- `Higher quality`: Gemma 2 2B, slower but a bit stronger
- `Custom`: manual Hugging Face GGUF repo entry

When you choose a brain profile, the installer also writes matching defaults for threads, context size, batch size, ubatch size, and chat history length into `.env`.

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
- pre-download the selected local ASR and LLM models
- generate a local `.env`
- build the chatbot
- install the systemd service

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
