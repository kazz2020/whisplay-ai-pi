import * as fs from "fs";
import * as path from "path";
import { getAudioDurationInSeconds } from "get-audio-duration";
import { ChildProcess, spawn } from "child_process";
import dotenv from "dotenv";
import { ttsDir } from "../../utils/dir";
import { TTSResult, TTSServer } from "../../type";
import { defaultPortMap } from "./common";

dotenv.config();

const sherpaOnnxHost = process.env.SHERPA_ONNX_TTS_HOST || "localhost";
const sherpaOnnxPort =
  process.env.SHERPA_ONNX_TTS_PORT || defaultPortMap.sherpaOnnxTts.toString();
const sherpaOnnxModelDir =
  process.env.SHERPA_ONNX_TTS_MODEL_DIR || "/home/pi/sherpa-onnx-tts/vits-piper-pl_PL-gosia-medium";
const sherpaOnnxNumThreads = process.env.SHERPA_ONNX_TTS_NUM_THREADS || "2";
const sherpaOnnxProvider = process.env.SHERPA_ONNX_TTS_PROVIDER || "cpu";
const sherpaOnnxSpeakerId = process.env.SHERPA_ONNX_TTS_SPEAKER_ID || "0";
const sherpaOnnxSpeed = process.env.SHERPA_ONNX_TTS_SPEED || "1.0";

const ttsServer = (process.env.TTS_SERVER || "").toLowerCase();

let pyProcess: ChildProcess | null = null;
if (ttsServer === TTSServer.sherpaonnx) {
  if (["localhost", "0.0.0.0", "127.0.0.1"].includes(sherpaOnnxHost)) {
    const scriptPath = path.resolve(__dirname, "../../../python/sherpa_onnx_tts_server.py");
    console.log("Starting Sherpa ONNX TTS server at port", sherpaOnnxPort);
    pyProcess = spawn(
      "python3",
      [scriptPath],
      {
        detached: true,
        stdio: "inherit",
        env: {
          ...process.env,
          SHERPA_ONNX_TTS_HOST: sherpaOnnxHost,
          SHERPA_ONNX_TTS_PORT: sherpaOnnxPort,
          SHERPA_ONNX_TTS_MODEL_DIR: sherpaOnnxModelDir,
          SHERPA_ONNX_TTS_NUM_THREADS: sherpaOnnxNumThreads,
          SHERPA_ONNX_TTS_PROVIDER: sherpaOnnxProvider,
          SHERPA_ONNX_TTS_SPEAKER_ID: sherpaOnnxSpeakerId,
          SHERPA_ONNX_TTS_SPEED: sherpaOnnxSpeed,
        },
      },
    );
  }
}

const sherpaOnnxTTS = async (text: string): Promise<TTSResult> => {
  return new Promise((resolve) => {
    const now = Date.now();
    const tempWavFile = path.join(ttsDir, `sherpa_onnx_${now}.wav`);

    const escapedText = text.replace(/"/g, '\\"');

    const curlProcess = spawn("curl", [
      "-sS",
      "-X",
      "POST",
      "-H",
      "Content-Type: application/json",
      "-d",
      `{ "text": "${escapedText}", "sid": ${sherpaOnnxSpeakerId}, "speed": ${sherpaOnnxSpeed} }`,
      "-o",
      tempWavFile,
      `http://${sherpaOnnxHost}:${sherpaOnnxPort}/tts`,
    ]);

    curlProcess.on("close", async (code: number) => {
      if (code !== 0 || !fs.existsSync(tempWavFile)) {
        console.error(`Sherpa ONNX TTS request failed with code ${code}`);
        resolve({ duration: 0 });
        return;
      }

      try {
        const duration = (await getAudioDurationInSeconds(tempWavFile)) * 1000;
        resolve({ filePath: tempWavFile, duration });
      } catch (error) {
        console.log("Error processing Sherpa ONNX output:", `\"${text}\"`, error);
        resolve({ duration: 0 });
      }
    });

    curlProcess.on("error", (error: any) => {
      console.log("Sherpa ONNX TTS process error:", `\"${text}\"`, error);
      resolve({ duration: 0 });
    });
  });
};

function cleanup() {
  if (pyProcess && !pyProcess.killed) {
    console.log("Killing Sherpa ONNX python server...");
    process.kill(-pyProcess.pid!, "SIGTERM");
  }
}

process.on("SIGINT", cleanup);
process.on("SIGTERM", cleanup);
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

export default sherpaOnnxTTS;