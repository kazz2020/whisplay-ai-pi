# Whisplay-AI-Chatbot

<img src="https://docs.pisugar.com/img/whisplay_logo@4x-8.png" alt="Whisplay AI Chatbot" width="200" />

[![Discord](https://img.shields.io/discord/1483017948305297501?logo=discord&logoColor=white&label=Discord&color=5865F2)](https://discord.gg/H7pb4M32)

This is a pocket-sized AI chatbot device built using a Raspberry Pi Zero 2w / 5. Just press the button, speak, and it talks back—like a futuristic walkie-talkie with a mind of its own.

Test Video Playlist:
[https://www.youtube.com/watch?v=lOVA0Gui-4Q](https://www.youtube.com/playlist?list=PLpTS9YM-tG_mW5H7Xs2EO0qvlAI-Jm1e_)

Tutorial:
[https://www.youtube.com/watch?v=Nwu2DruSuyI](https://www.youtube.com/watch?v=Nwu2DruSuyI)

Tutorial (offline version build on RPi 5):

[https://youtu.be/kFmhSTh167U](https://youtu.be/kFmhSTh167U)

[https://youtu.be/QNbHdJUW6z8](https://youtu.be/QNbHdJUW6z8)

[https://youtu.be/xGzvFzdBAwc](https://youtu.be/xGzvFzdBAwc)


## Hardware

- Raspberry Pi zero 2w (Recommand RRi 5, 8G RAM for offline build)
- PiSugar Whisplay HAT (including LCD screen, on-board speaker and microphone)
- PiSugar 3 1200mAh (Plus version 5000mAh for RPi 5)

## Pre-build Image

- Please find the pre-build images in project wiki: https://github.com/PiSugar/whisplay-ai-chatbot/wiki

## Drivers

You need to firstly install the audio drivers for the Whisplay HAT. Follow the instructions in the [Whisplay HAT repository](https://github.com/PiSugar/whisplay).

## Installation Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/PiSugar/whisplay-ai-chatbot.git
   cd whisplay-ai-chatbot
   ```
2. Install dependencies:
   ```bash
   bash install_dependencies.sh
   source ~/.bashrc
   ```
   Running `source ~/.bashrc` is necessary to load the new environment variables.

   **Custom npm registry:** All scripts respect the `NPM_REGISTRY` environment variable. If not set, the official npm registry (`https://registry.npmjs.org`) is used. To use a mirror (e.g. in China), export it before running any script:
   ```bash
   export NPM_REGISTRY="https://registry.npmmirror.com"
   bash install_dependencies.sh
   ```
   This also applies to `build.sh` and all `whisplay` CLI commands (`plugin install`, `plugin update`, `update`, etc.).

3. Create a `.env` file based on the `.env.template` file and fill in the necessary environment variables.
4. Build the project:
   ```bash
   bash build.sh
   ```
5. Start the chatbot service:
   ```bash
   bash run_chatbot.sh
   ```
   For live terminal debugging on the Pi, run:
   ```bash
   bash run_chatbot.sh --debug
   ```
   This keeps the launcher in the foreground and prefixes output from the main app and local helper services so you can see what is happening in real time.
   For verbose button/audio/display tracing, run:
   ```bash
   bash run_chatbot.sh --trace
   ```
   This enables structured trace logs for button presses, display socket traffic, camera mode changes, and audio record/playback events.
6. Optionally, set up the chatbot service to start on boot:
   ```bash
   bash startup.sh
   ```
   Please note that this will disable the graphical interface and set the system to multi-user mode, which is suitable for headless operation.
   You can find the output logs at `chatbot.log`. Running `tail -f chatbot.log` will also display the logs in real-time.

## Raspberry Pi 5 Local Assistant

This repository now includes a fully local Raspberry Pi 5 8GB path using:

- Whisplay HAT driver installation
- local ASR with faster-whisper
- local LLM with `llama.cpp` `llama-server` or LiteRT-LM
- local TTS with Piper HTTP

For a fresh Raspberry Pi OS install, run:

```bash
bash pi5-universal-installer.sh
```

The installer lets you choose whether to install the HAT driver, chatbot dependencies, local ASR/TTS, llama.cpp, LiteRT-LM, the chatbot build, and the startup service.

The Pi installer now supports two different fully local LLM backends:

- `llama.cpp` for GGUF-based local models served by `llama-server`
- `litert-lm` for `.litertlm` models such as Gemma 3n or Gemma 4 LiteRT builds

The installer can also enable wake word detection. If you want the most reliable ready-made English option, choose `openWakeWord` with a preset like `hey_jarvis`. If you want your own custom phrase, choose `local-wake` and record reference samples directly on the device.

The local Pi presets now also support answer interruption during TTS. Pressing the button while the assistant is speaking will stop the current reply immediately, and the Pi presets can also interrupt playback automatically when you start talking over the answer.

The installer now also supports two local TTS backends on the Pi:

- `piper-http` for the existing Piper flow
- `sherpa-onnx` for an alternative offline backend you can compare on the same device

For Sherpa ONNX, the installer can download Polish preset models such as `vits-piper-pl_PL-gosia-medium` and `vits-piper-pl_PL-darkman-medium`, write the matching `.env` values, and let you switch back later by rerunning the installer or changing `TTS_SERVER`.

For Polish, the safer default is `local-wake` with a Polish phrase you record yourself. The installer now also writes Polish end-of-conversation keywords and uses a slightly stricter default threshold for Polish local-wake phrases.

If you choose `openWakeWord`, the installer can now pre-download the preset model during setup so first boot does not depend on network access.

The recommended local preset is stored in `.env.pi5-local.template`. A Polish-focused preset is available in `.env.pi5-local-pl.template`. Detailed notes are in `docs/pi5-local-assistant.md`.

To re-record local wake phrase samples later, run:

```bash
bash scripts/setup_local_wakeword.sh
```

The Pi 5 installer now also includes an `Ollama Cloud` brain option. If you choose it, the installer prompts for `OLLAMA_API_KEY` and lets you pick a curated cloud model such as `gemma3:27b-cloud`, `gemma4:26b-cloud`, `qwen3.5:27b-cloud`, or `glm-5.1:cloud`, then writes the cloud model settings into `.env` automatically.

The installer also now includes a `LiteRT-LM` brain option as a second local method. If you choose it, the installer can install the `litert-lm` Python runtime, download a LiteRT model from Hugging Face, and write the matching `LITERT_LM_*` settings into `.env`.

The LiteRT catalog now includes lower-RAM and multilingual variants such as:

- `Gemma 3n E2B Preview` for the smallest local footprint
- `Gemma 3n E2B LiteRT-LM` for fast Pi 5 use
- `Polish-first` and `German-first` Pi-friendly presets based on the multilingual Gemma 3n E2B LiteRT model
- `Gemma 3n E4B LiteRT-LM` for a stronger multilingual option
- `Gemma 4 E2B` and `Gemma 4 E4B` LiteRT variants for balanced and higher-quality local use

After installation, you can switch to another local LiteRT-LM model later by running:

```bash
bash switch_litert_model.sh
```

The script updates `LITERT_LM_MODEL_PATH` and `LITERT_LM_MODEL_REPO` in `.env`, can download a preset model from Hugging Face, and can restart `chatbot.service` for you.

To only print the LiteRT model files already downloaded on the Pi, run:

```bash
bash switch_litert_model.sh --list-local
```

After installation, you can switch to another Ollama model later by running:

```bash
bash switch_ollama_model.sh
```

The script reads your current `.env`, shows a numbered menu of models from the configured Ollama endpoint when available, falls back to built-in cloud presets if listing fails, updates `OLLAMA_MODEL`, and can restart `chatbot.service` for you.

## Ollama Cloud on Pi 5

If you want the Pi 5 device experience but do not want to run the LLM locally, you can use Ollama Cloud with the built-in Ollama provider. This keeps ASR, TTS, button handling, display, and device control on the Pi, while the text generation runs remotely.

Example `.env` settings for GLM 5.1 Cloud:

```bash
LLM_SERVER=ollama-cloud
OLLAMA_ENDPOINT=https://ollama.com
OLLAMA_MODEL=glm-5.1:cloud
OLLAMA_API_KEY=your_ollama_api_key
```

Notes:

- The code calls the standard Ollama API path (`/api/chat`, `/api/generate`), so cloud usage relies on the same Ollama-compatible protocol as local Ollama.
- This is a good fit for Raspberry Pi 5 because the Pi does not need enough RAM or GPU to host a 27B model locally.
- End-to-end latency will depend on Wi-Fi quality and Ollama Cloud response time, so it will feel less instant than a small local model.
- If you want vision through Ollama too, set `VISION_SERVER=ollama` and optionally `OLLAMA_VISION_MODEL=glm-5.1:cloud` if that model path is enabled for your account.

For Polish voice use on a Pi 5 8GB, the practical sweet spot is:

- `FASTER_WHISPER_LANGUAGE=pl`
- `FASTER_WHISPER_MODEL_SIZE_OR_PATH=base` for the best speed or `small` for higher recognition quality
- `LLM_SERVER=ollama-cloud` with `OLLAMA_MODEL=glm-5.1:cloud`
- `ENABLE_THINKING=false` and `USE_CAPTURED_IMAGE_IN_CHAT=false` to keep latency and RAM usage down
- short chat history so each request stays small

The Pi installer now includes a Polish speed profile and an optional Raspberry Pi memory tuning step with balanced or aggressive profiles. It configures zram, disk swap fallback, extra VM cache/writeback tuning, and lower-fragmentation allocator defaults for long-running Node/Python processes. This improves effective working headroom on Pi 5 8GB, but it does not increase the physical RAM limit.

## RAG Knowledge Base

The project includes built-in RAG support. The recommended setup for Raspberry Pi is:

- Qdrant as the vector database
- Ollama embeddings with a lightweight embedding model such as `nomic-embed-text`
- your main answer model kept separate from embeddings, for example `glm-5.1:cloud` for final responses

Recommended flow:

1. Put `.txt` or `.md` files into the `knowledge/` directory.
2. Enable RAG in `.env`.
3. Configure `QDRANT_HOST`, `OLLAMA_EMBEDDING_ENDPOINT`, and `OLLAMA_EMBEDDING_MODEL`.
4. Build the knowledge index with `bash index_knowledge.sh`.

The Pi installer now includes a RAG setup step and writes the relevant `.env` values for you.

For embeddings, the installer now supports two practical paths:

- native Ollama on the Pi itself for local `nomic-embed-text` style embeddings
- another Ollama endpoint on your LAN if you want embeddings off-device

If you choose native Ollama in the installer, it uses `scripts/install_ollama.sh`, points `OLLAMA_EMBEDDING_ENDPOINT` at `http://127.0.0.1:11434`, and can pre-download the embedding model during setup.

If you want the easiest local or LAN vector database setup, the repository Docker compose stack now includes a `qdrant` service listening on port `6333`.

If you enable RAG in the Pi installer, it can also set `SERVE_QDRANT=true` so `bash run_chatbot.sh` starts the local Qdrant container automatically when Docker Compose is available.

## Build After Code Changes

If you make changes to the node code or just pull the new code from this repository, you need to rebuild the project. You can do this by running:

```bash
bash build.sh
```

If If you encounter `ModuleNotFoundError` or there's new third-party libraries to the python code, please run the following command to update the dependencies for python:
```
cd python
pip install -r requirements.txt --break-system-packages
```

The env template may be updated from time to time. If you want to upgrade your existing `.env` file based on the latest `.env.template`, you can run the following command:

```bash
bash upgrade-env.sh
```

## Update Environment Variables

If you need to update the environment variables, you can edit the `.env` file directly. After making changes, please restart the chatbot service with:

```bash
sudo systemctl restart chatbot.service
```

## More Features

**[Wake Word](https://github.com/PiSugar/whisplay-ai-chatbot/wiki/Wakeword)** for hands-free interaction.

**[Image Generation](https://github.com/PiSugar/whisplay-ai-chatbot/wiki/Image-Generation)** for generating images from text prompts.

**[Battery Level Display](https://github.com/PiSugar/whisplay-ai-chatbot/wiki/Battery-Level-Display)** for installation instructions.

**[Data Folder](https://github.com/PiSugar/whisplay-ai-chatbot/wiki/Data-Folder)** for details on sub-folder layout and cleanup options.

## Enclosure

[Whisplay Chatbot Case for Pi02](https://github.com/PiSugar/suit-cases/tree/main/pisugar3-whisplay-chatbot)

[Whisplay Chatbot Case (FDM) for Pi02](https://github.com/PiSugar/suit-cases/tree/main/pisugar3-whisplay-chatbot-fdm)

[Whisplay Chatbot Case (FDM) for Pi5](https://github.com/PiSugar/suit-cases/tree/main/pi5-whisplay-chatbot)

[Whisplay Chatbot Case (FDM) for Pi5 & LLM8850](https://github.com/PiSugar/suit-cases/tree/main/pi5-whisplay-chatbot-llm8850)

## AI Accelerator Card Support

[LLM8850](https://github.com/PiSugar/whisplay-ai-chatbot/wiki/LLM8850-Integration)

[Raspberry Pi AI HAT+ 2 (Hailo-10H)](https://github.com/PiSugar/whisplay-ai-chatbot/wiki/Raspberry-Pi-AI-HAT+-2)

## Goals

- Support LLM8850 whisper ✅
- Support LLM8850 melottsTTS ✅
- Support LLM8850 Qwen3 llm api (not support tool) ✅
- Support LLM8850 Qwen3-VL multimodal llm api (not support tool) ✅ 
- Support LLM8850 image generation ✅
- Suppprt Raspberry Pi AI Hat+2 (Hailo-10H) whisper, llm, vlm ✅
- Support speaker recognition

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=PiSugar/whisplay-ai-chatbot&type=date&legend=bottom-right)](https://www.star-history.com/#PiSugar/whisplay-ai-chatbot&type=date&legend=bottom-right)

## License

[GPL-3.0](https://github.com/PiSugar/whisplay-ai-chatbot?tab=GPL-3.0-1-ov-file#readme)
