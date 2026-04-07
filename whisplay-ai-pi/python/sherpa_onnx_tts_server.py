import io
import os
from pathlib import Path

import soundfile as sf
from flask import Flask, jsonify, request, send_file

try:
    import sherpa_onnx
except Exception as exc:
    raise RuntimeError(f"Failed to import sherpa_onnx: {exc}") from exc

app = Flask(__name__)


def require_env(name: str, default: str = "") -> str:
    value = os.getenv(name, default).strip()
    if value:
        return value
    raise RuntimeError(f"Missing required environment variable: {name}")


MODEL_DIR = Path(require_env("SHERPA_ONNX_TTS_MODEL_DIR"))
HOST = os.getenv("SHERPA_ONNX_TTS_HOST", "127.0.0.1")
PORT = int(os.getenv("SHERPA_ONNX_TTS_PORT", "8809"))
NUM_THREADS = int(os.getenv("SHERPA_ONNX_TTS_NUM_THREADS", "2"))
PROVIDER = os.getenv("SHERPA_ONNX_TTS_PROVIDER", "cpu")


def find_file(pattern: str) -> str:
    matches = sorted(MODEL_DIR.glob(pattern))
    if not matches:
        raise RuntimeError(f"Missing {pattern} in {MODEL_DIR}")
    return str(matches[0])


config = sherpa_onnx.OfflineTtsConfig(
    model=sherpa_onnx.OfflineTtsModelConfig(
        vits=sherpa_onnx.OfflineTtsVitsModelConfig(
            model=find_file("*.onnx"),
            lexicon="",
            data_dir=str(MODEL_DIR / "espeak-ng-data"),
            tokens=find_file("tokens.txt"),
        ),
        provider=PROVIDER,
        num_threads=NUM_THREADS,
    ),
)

if not config.validate():
    raise RuntimeError(f"Invalid sherpa-onnx TTS config for {MODEL_DIR}")

tts = sherpa_onnx.OfflineTts(config)


@app.get("/health")
def health():
    return jsonify({"ok": True, "model_dir": str(MODEL_DIR)})


@app.post("/tts")
def synthesize():
    payload = request.get_json(force=True, silent=True) or {}
    text = str(payload.get("text", "")).strip()
    sid = int(payload.get("sid", 0))
    speed = float(payload.get("speed", 1.0))

    if not text:
        return jsonify({"error": "text is required"}), 400

    audio = tts.generate(text=text, sid=sid, speed=speed)
    buffer = io.BytesIO()
    sf.write(buffer, audio.samples, audio.sample_rate, format="WAV")
    buffer.seek(0)
    return send_file(buffer, mimetype="audio/wav", download_name="tts.wav")


if __name__ == "__main__":
    app.run(host=HOST, port=PORT)