import { EventEmitter } from "events";
import { spawn, ChildProcess } from "child_process";
import { resolve } from "path";
import { existsSync, readdirSync } from "fs";
import dotenv from "dotenv";
import { traceEvent } from "../utils/trace";
dotenv.config();

const pythonBinary = process.env.WAKE_WORD_PYTHON_PATH || "python3";

export class WakeWordListener extends EventEmitter {
  private process: ChildProcess | null = null;
  private buffer: string = "";

  start(): void {
    if (this.process) return;
    const enabled = (process.env.WAKE_WORD_ENABLED || "").toLowerCase();
    if (enabled !== "true") return;

    const engine = (process.env.WAKE_WORD_ENGINE || "openwakeword").toLowerCase();
    if (engine === "local-wake") {
      const referenceDir = process.env.WAKE_WORD_REFERENCE_DIR || "";
      if (!referenceDir || !existsSync(referenceDir)) {
        console.error(
          `[WakeWord] local-wake is enabled, but WAKE_WORD_REFERENCE_DIR is missing or does not exist: ${referenceDir || "<empty>"}`,
        );
        console.error("[WakeWord] Record samples with: bash scripts/setup_local_wakeword.sh 4 3");
        return;
      }

      const wavFiles = readdirSync(referenceDir).filter((name) =>
        name.toLowerCase().endsWith(".wav"),
      );
      if (wavFiles.length === 0) {
        console.error(
          `[WakeWord] local-wake is enabled, but no .wav samples were found in ${referenceDir}`,
        );
        console.error("[WakeWord] Record samples with: bash scripts/setup_local_wakeword.sh 4 3");
        return;
      }
    }

    const scriptPath = resolve(__dirname, "../../python/wakeword.py");
    traceEvent("wakeword", "Starting wake word listener", {
      engine,
      pythonBinary,
      scriptPath,
    });
    this.process = spawn(pythonBinary, [scriptPath], {
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });

    this.process.stdout?.on("data", (data: Buffer) => {
      this.buffer += data.toString();
      let newlineIndex = this.buffer.indexOf("\n");
      while (newlineIndex !== -1) {
        const line = this.buffer.slice(0, newlineIndex).trim();
        this.buffer = this.buffer.slice(newlineIndex + 1);
        if (line.startsWith("WAKE")) {
          traceEvent("wakeword", "Wake word detected", { line });
          this.emit("wake", line);
        } else if (line) {
          console.log(`[WakeWord] ${line}`);
        }
        newlineIndex = this.buffer.indexOf("\n");
      }
    });

    this.process.stderr?.on("data", (data: Buffer) => {
      const message = data.toString().trim();
      if (message) {
        traceEvent("wakeword", "Wake word stderr", { message });
        console.error(`[WakeWord] ${message}`);
      }
    });

    this.process.on("close", (code) => {
      traceEvent("wakeword", "Wake word listener exited", { code });
      console.log(`[WakeWord] process exited with code ${code}`);
      if (code && engine === "local-wake") {
        console.error("[WakeWord] local-wake exited unexpectedly. Run `bash run_chatbot.sh --debug` to inspect microphone and threshold logs.");
      }
      this.process = null;
    });
  }

  stop(): void {
    if (!this.process) return;
    traceEvent("wakeword", "Stopping wake word listener");
    this.process.kill("SIGTERM");
    this.process = null;
  }
}
