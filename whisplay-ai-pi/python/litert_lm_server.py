import atexit
import json
import os
import threading
from pathlib import Path
from typing import Any

from flask import Flask, Response, jsonify, request, stream_with_context

try:
    import litert_lm
except Exception as exc:
    raise RuntimeError(f"Failed to import litert_lm: {exc}") from exc

app = Flask(__name__)


def require_env(name: str, default: str = "") -> str:
    value = os.getenv(name, default).strip()
    if value:
        return value
    raise RuntimeError(f"Missing required environment variable: {name}")


MODEL_PATH = Path(require_env("LITERT_LM_MODEL_PATH"))
MODEL_REPO = os.getenv("LITERT_LM_MODEL_REPO", "").strip()
HOST = os.getenv("LITERT_LM_HOST", "127.0.0.1")
PORT = int(os.getenv("LITERT_LM_PORT", "8810"))
BACKEND_NAME = os.getenv("LITERT_LM_BACKEND", "cpu").strip().upper()
CACHE_DIR = os.getenv("LITERT_LM_CACHE_DIR", "").strip()
SPECULATIVE_DECODING = (
    os.getenv("LITERT_LM_ENABLE_SPECULATIVE_DECODING", "auto").strip().lower()
)

if hasattr(litert_lm, "set_min_log_severity") and hasattr(litert_lm, "LogSeverity"):
    litert_lm.set_min_log_severity(litert_lm.LogSeverity.ERROR)

engine_lock = threading.Lock()
request_lock = threading.Lock()
engine_ctx = None
engine = None


def parse_backend() -> Any:
    if hasattr(litert_lm.Backend, BACKEND_NAME):
        return getattr(litert_lm.Backend, BACKEND_NAME)
    return litert_lm.Backend.CPU


def parse_speculative_decoding() -> Any:
    if SPECULATIVE_DECODING == "auto":
        return None
    return SPECULATIVE_DECODING in {"1", "true", "yes", "y", "on"}


def get_engine():
    global engine_ctx, engine

    with engine_lock:
      if engine is not None:
          return engine

      if not MODEL_PATH.exists():
          raise RuntimeError(f"LiteRT-LM model not found: {MODEL_PATH}")

      engine_kwargs = {
          "backend": parse_backend(),
      }
      if CACHE_DIR:
          engine_kwargs["cache_dir"] = CACHE_DIR

      speculative = parse_speculative_decoding()
      if speculative is not None:
          engine_kwargs["enable_speculative_decoding"] = speculative

      engine_ctx = litert_lm.Engine(str(MODEL_PATH), **engine_kwargs)
      engine = engine_ctx.__enter__()
      return engine


def cleanup_engine() -> None:
    global engine_ctx, engine

    with engine_lock:
        if engine_ctx is not None:
            engine_ctx.__exit__(None, None, None)
            engine_ctx = None
            engine = None


atexit.register(cleanup_engine)


def message_to_litert(message: dict[str, Any]) -> dict[str, Any]:
    content = message.get("content", "")
    if isinstance(content, str):
        litert_content = [{"type": "text", "text": content}]
    elif isinstance(content, list):
        litert_content = content
    else:
        litert_content = [{"type": "text", "text": json.dumps(content, ensure_ascii=False)}]

    converted: dict[str, Any] = {
        "role": message.get("role", "user"),
        "content": litert_content,
    }
    if message.get("tool_calls"):
        converted["tool_calls"] = message["tool_calls"]
    if message.get("tool_call_id"):
        converted["tool_call_id"] = message["tool_call_id"]
    return converted


def extract_text(message: dict[str, Any]) -> str:
    content = message.get("content", [])
    if isinstance(content, list):
        parts = [item.get("text", "") for item in content if item.get("type") == "text"]
        return "".join(parts)
    if isinstance(content, str):
        return content
    return ""


@app.get("/health")
def health():
    return jsonify(
        {
            "ok": True,
            "model_path": str(MODEL_PATH),
            "model_repo": MODEL_REPO,
            "backend": BACKEND_NAME.lower(),
        }
    )


@app.post("/reset")
def reset():
    return jsonify({"ok": True, "stateless": True})


@app.post("/generate")
def generate_text():
    payload = request.get_json(force=True, silent=True) or {}
    prompt = str(payload.get("prompt", "")).strip()
    if not prompt:
        return jsonify({"error": "prompt is required"}), 400

    with request_lock:
        with get_engine().create_conversation() as conversation:
            response = conversation.send_message(prompt)
            return jsonify({"text": extract_text(response)})


@app.post("/chat")
def chat():
    payload = request.get_json(force=True, silent=True) or {}
    raw_messages = payload.get("messages") or []
    if not isinstance(raw_messages, list) or not raw_messages:
        return jsonify({"error": "messages array is required"}), 400

    messages = [message_to_litert(message) for message in raw_messages]
    history = messages[:-1]
    next_message = messages[-1]

    @stream_with_context
    def generate():
        try:
            with request_lock:
                with get_engine().create_conversation(messages=history) as conversation:
                    stream = conversation.send_message_async(next_message)
                    for chunk in stream:
                        content = chunk.get("content", [])
                        for item in content:
                            if item.get("type") == "text" and item.get("text"):
                                yield json.dumps({"content": item["text"]}, ensure_ascii=False) + "\n"
                    yield json.dumps({"done": True}, ensure_ascii=False) + "\n"
        except Exception as exc:
            yield json.dumps({"error": str(exc), "done": True}, ensure_ascii=False) + "\n"

    return Response(generate(), mimetype="application/x-ndjson")


if __name__ == "__main__":
    app.run(host=HOST, port=PORT, threaded=True)