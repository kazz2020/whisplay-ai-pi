import * as fs from "fs";
import * as path from "path";
import { getAudioDurationInSeconds } from "get-audio-duration";
import { ChildProcess, spawn } from "child_process";
import dotenv from "dotenv";
import { ttsDir } from "../../utils/dir";
import { TTSResult, TTSServer } from "../../type";
import { defaultPortMap } from "./common";
import { traceEvent } from "../../utils/trace";

dotenv.config();

const piperHttpHost = process.env.PIPER_HTTP_HOST || "localhost";
const piperHttpPort = process.env.PIPER_HTTP_PORT || defaultPortMap.piperHttp.toString();
const piperHttpModel =
  process.env.PIPER_HTTP_MODEL || "en_US-amy-medium";
const piperHttpLengthScale =
  process.env.PIPER_HTTP_LENGTH_SCALE || "1";
const piperHttpBaseUrl =
  process.env.PIPER_HTTP_BASE_URL || `http://${piperHttpHost}:${piperHttpPort}`;

const ttsServer = (process.env.TTS_SERVER || "").toLowerCase();

let pyProcess: ChildProcess | null = null;
if (ttsServer === TTSServer.piperhttp) {
  if (
    ["localhost", "0.0.0.0", "127.0.0.1"].includes(piperHttpHost)
  ) {
    console.log("Starting Piper HTTP server at port", piperHttpPort);
    // python3 -m piper.http_server -m en_US-lessac-medium
    pyProcess = spawn(
      "python3",
      [
        "-m",
        "piper.http_server",
        "-m",
        piperHttpModel,
        "--port",
        piperHttpPort,
        "--host",
        piperHttpHost,
      ],
      {
        detached: true,
        stdio: "inherit",
      }
    );
  }
}

const piperHttpTTS = async (
  text: string
): Promise<TTSResult> => {
  const now = Date.now();
  const tempWavFile = path.join(ttsDir, `piper_http_${now}.wav`);
  const convertedWavFile = path.join(ttsDir, `piper_http_${now}_converted.wav`);

  try {
    traceEvent("tts", "Piper HTTP request started", {
      baseUrl: piperHttpBaseUrl,
      textLength: text.length,
      lengthScale: piperHttpLengthScale,
    });

    const response = await fetch(`${piperHttpBaseUrl}/`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        text,
        length_scale: parseFloat(piperHttpLengthScale),
      }),
    });

    if (!response.ok) {
      console.error(`Piper HTTP request failed with status ${response.status}`);
      traceEvent("tts", "Piper HTTP request failed", {
        status: response.status,
        statusText: response.statusText,
      });
      return { duration: 0 };
    }

    const audioBuffer = Buffer.from(await response.arrayBuffer());
    fs.writeFileSync(tempWavFile, audioBuffer);
    traceEvent("tts", "Piper HTTP response received", {
      bytes: audioBuffer.length,
      tempWavFile,
    });

    if (fs.existsSync(tempWavFile) === false) {
      console.log("Piper output file not found:", tempWavFile);
      return { duration: 0 };
    }

    const originalBuffer = fs.readFileSync(tempWavFile);
    const header = originalBuffer.subarray(0, 44);
    const originalSampleRate = header.readUInt32LE(24);
    const originalChannels = header.readUInt16LE(22);

    await new Promise<void>((resolve, reject) => {
      const soxProcess = spawn("sox", [
        "-v",
        "0.9",
        tempWavFile,
        "-r",
        originalSampleRate.toString(),
        "-c",
        originalChannels.toString(),
        convertedWavFile,
      ]);

      soxProcess.on("close", (soxCode: number) => {
        if (soxCode !== 0) {
          console.error(`Sox process exited with code ${soxCode}`);
          reject(new Error(`Sox process exited with code ${soxCode}`));
        } else {
          fs.unlinkSync(tempWavFile);
          resolve();
        }
      });
    });

    const duration = (await getAudioDurationInSeconds(convertedWavFile)) * 1000;
    traceEvent("tts", "Piper HTTP audio prepared", {
      convertedWavFile,
      duration,
    });

    return { filePath: convertedWavFile, duration };
  } catch (error) {
    console.log("Error processing Piper output:", `"${text}"`, error);
    traceEvent("tts", "Piper HTTP synthesis error", {
      message: error instanceof Error ? error.message : String(error),
    });
    return { duration: 0 };
  }
};

function cleanup() {
  if (pyProcess && !pyProcess.killed) {
    console.log("Killing python server...");
    process.kill(-pyProcess.pid!, "SIGTERM");
  }
}

process.on("SIGINT", cleanup); // Ctrl+C
process.on("SIGTERM", cleanup); // systemctl / docker stop
process.on("exit", cleanup);
process.on("uncaughtException", (err) => {
  console.error(err);
  cleanup();
  process.exit(1);
});
process.on("unhandledRejection", (err) => {
  console.error(err);
  cleanup();
  process.exit(1);
});


export default piperHttpTTS;
