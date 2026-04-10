import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

import numpy as np


def parse_float(value: str, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def parse_list(value: str):
    return [item.strip() for item in value.split(",") if item.strip()]


def log(message: str):
    print(f"[WakeWord] {message}", flush=True)


def log_error(message: str):
    print(f"[WakeWord] {message}", file=sys.stderr, flush=True)


def is_trace_enabled() -> bool:
    return os.getenv("WHISPLAY_TRACE_EVENTS", "").lower() == "true"


def normalize_engine() -> str:
    configured = os.getenv("WAKE_WORD_ENGINE", "").strip().lower()
    if configured:
        return configured
    if os.getenv("WAKE_WORD_REFERENCE_DIR", "").strip():
        return "local-wake"
    return "openwakeword"


def resolve_local_wake_bin() -> str:
    configured = os.getenv("WAKE_WORD_LOCAL_WAKE_BIN", "").strip()
    if configured:
        return configured

    detected = shutil.which("lwake")
    if detected:
        return detected

    raise RuntimeError(
        "local-wake binary 'lwake' not found. Install local-wake first or set WAKE_WORD_LOCAL_WAKE_BIN."
    )


def forward_stream(stream, is_error: bool = False):
    if stream is None:
        return

    for line in iter(stream.readline, ""):
        message = line.strip()
        if not message:
            continue
        if is_error:
            log_error(message)
        else:
            log(message)


def run_local_wake() -> int:
    reference_dir = os.getenv("WAKE_WORD_REFERENCE_DIR", "").strip()
    if not reference_dir:
        raise RuntimeError("WAKE_WORD_REFERENCE_DIR is required for local-wake")

    reference_path = Path(reference_dir).expanduser().resolve()
    if not reference_path.is_dir():
        raise RuntimeError(f"Wake word reference directory not found: {reference_path}")

    wav_files = sorted(reference_path.glob("*.wav"))
    if not wav_files:
        raise RuntimeError(
            f"No .wav reference samples found in {reference_path}. Record samples first."
        )

    threshold = parse_float(os.getenv("WAKE_WORD_THRESHOLD", "0.12"), 0.12)
    cooldown_sec = parse_float(os.getenv("WAKE_WORD_COOLDOWN_SEC", "2.0"), 2.0)
    buffer_size = os.getenv("WAKE_WORD_LOCAL_WAKE_BUFFER_SIZE", "1.8")
    slide_size = os.getenv("WAKE_WORD_LOCAL_WAKE_SLIDE_SIZE", "0.25")
    method = os.getenv("WAKE_WORD_LOCAL_WAKE_METHOD", "embedding").strip() or "embedding"
    trigger_distance_raw = os.getenv("WAKE_WORD_LOCAL_WAKE_TRIGGER_DISTANCE", "").strip()
    debug_enabled = os.getenv("WAKE_WORD_LOCAL_WAKE_DEBUG", "false").lower() == "true"
    phrase = os.getenv("WAKE_WORD_PHRASE", "").strip() or reference_path.name

    if trigger_distance_raw:
        trigger_distance = parse_float(trigger_distance_raw, threshold)
    elif threshold > 0.10:
        trigger_distance = 0.09
    else:
        trigger_distance = threshold

    trigger_distance = min(trigger_distance, threshold)
    if trigger_distance <= 0:
        trigger_distance = threshold

    local_wake_bin = resolve_local_wake_bin()
    command = [
        local_wake_bin,
        "listen",
        str(reference_path),
        str(threshold),
        "--method",
        method,
        "--buffer-size",
        buffer_size,
        "--slide-size",
        slide_size,
    ]
    if debug_enabled:
        command.append("--debug")

    log(
        f"Engine=local-wake phrase='{phrase}' refs={len(wav_files)} threshold={threshold:.3f} trigger_distance={trigger_distance:.3f} cooldown={cooldown_sec:.1f}s"
    )
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    def cleanup(*_):
        try:
            process.terminate()
        except Exception:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    stderr_thread = threading.Thread(
        target=forward_stream,
        args=(process.stderr, True),
        daemon=True,
    )
    stderr_thread.start()

    print("[WakeWord] READY", flush=True)

    if process.stdout is None:
        raise RuntimeError("local-wake process did not expose stdout")

    last_trigger = 0.0

    for line in iter(process.stdout.readline, ""):
        message = line.strip()
        if not message:
            continue
        try:
            payload = json.loads(message)
        except json.JSONDecodeError:
            log(message)
            continue

        wake_label = payload.get("wakeword") or phrase
        distance = payload.get("distance")
        timestamp = payload.get("timestamp")
        if distance is not None:
            distance = parse_float(str(distance), threshold)
            if distance > trigger_distance:
                if is_trace_enabled():
                    log(
                        f"Ignoring loose match phrase='{phrase}' matched='{wake_label}' distance={distance:.4f} trigger_distance={trigger_distance:.4f}"
                    )
                continue
            now = time.time()
            if now - last_trigger < cooldown_sec:
                continue
            last_trigger = now
            print(f"WAKE {phrase} {distance}", flush=True)
            if is_trace_enabled():
                log(
                    f"Detection phrase='{phrase}' matched='{wake_label}' distance={distance} timestamp={timestamp}"
                )
        else:
            log(f"Detection payload: {payload}")

    return process.wait()


def run_openwakeword() -> int:
    try:
        import openwakeword
        from openwakeword.model import Model
        from openwakeword.utils import download_models
    except Exception as exc:
        raise RuntimeError(f"Failed to import openwakeword: {exc}") from exc

    wake_words = parse_list(os.getenv("WAKE_WORDS", ""))
    model_paths = parse_list(os.getenv("WAKE_WORD_MODEL_PATHS", ""))
    threshold = float(os.getenv("WAKE_WORD_THRESHOLD", "0.45"))
    cooldown_sec = float(os.getenv("WAKE_WORD_COOLDOWN_SEC", "1.5"))
    vad_threshold = float(os.getenv("WAKE_WORD_VAD_THRESHOLD", "0.2"))
    enable_speex = os.getenv("WAKE_WORD_ENABLE_SPEEX", "true").lower() == "true"

    if not wake_words and not model_paths:
        wake_words = ["hey_jarvis"]

    if not model_paths:
        download_models(model_names=wake_words)

    log(
        f"Engine=openwakeword models={model_paths or wake_words} threshold={threshold} vad={vad_threshold} speex={enable_speex}"
    )
    try:
        model = Model(
            wakeword_models=model_paths or wake_words,
            enable_speex_noise_suppression=enable_speex,
            vad_threshold=vad_threshold,
        )
    except ModuleNotFoundError as exc:
        if enable_speex and getattr(exc, "name", "") == "speexdsp_ns":
            log_error(
                "speexdsp_ns is not installed; retrying openWakeWord without Speex noise suppression"
            )
            model = Model(
                wakeword_models=model_paths or wake_words,
                enable_speex_noise_suppression=False,
                vad_threshold=vad_threshold,
            )
        else:
            raise

    sox_cmd = [
        "sox",
        "-t",
        "alsa",
        "default",
        "-r",
        "16000",
        "-b",
        "16",
        "-e",
        "signed-integer",
        "-c",
        "1",
        "-t",
        "raw",
        "-",
    ]

    process = subprocess.Popen(
        sox_cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )

    def cleanup(*_):
        try:
            process.terminate()
        except Exception:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    last_trigger = 0.0
    chunk_samples = 1280
    chunk_bytes = chunk_samples * 2

    print("[WakeWord] READY", flush=True)

    while True:
        if process.stdout is None:
            time.sleep(0.1)
            continue
        data = process.stdout.read(chunk_bytes)
        if not data or len(data) < chunk_bytes:
            time.sleep(0.01)
            continue

        audio = np.frombuffer(data, dtype=np.int16)
        try:
            prediction = model.predict(audio)
        except Exception:
            continue

        now = time.time()
        if now - last_trigger < cooldown_sec:
            continue

        for keyword, score in prediction.items():
            if score >= threshold:
                last_trigger = now
                print(f"WAKE {keyword} {score:.3f}", flush=True)
                break


def main():
    engine = normalize_engine()
    if engine == "local-wake":
        return run_local_wake()
    if engine in {"openwakeword", "open-wake-word"}:
        return run_openwakeword()
    raise RuntimeError(
        f"Unsupported WAKE_WORD_ENGINE='{engine}'. Use 'local-wake' or 'openwakeword'."
    )


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        log_error(str(exc))
        sys.exit(1)
