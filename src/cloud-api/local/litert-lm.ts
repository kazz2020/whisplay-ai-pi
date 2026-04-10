import axios from "axios";
import { ChildProcess, spawn } from "child_process";
import dotenv from "dotenv";
import * as fs from "fs";
import * as path from "path";
import moment from "moment";
import {
  shouldResetChatHistory,
  systemPrompt,
  updateLastMessageTime,
} from "../../config/llm-config";
import { Message } from "../../type";
import {
  ChatWithLLMStreamFunction,
  SummaryTextWithLLMFunction,
} from "../interface";
import { chatHistoryDir } from "../../utils/dir";
import { defaultPortMap } from "./common";

dotenv.config();

const litertHost = process.env.LITERT_LM_HOST || "127.0.0.1";
const litertPort =
  process.env.LITERT_LM_PORT || defaultPortMap.litertLm.toString();
const litertModelPath =
  process.env.LITERT_LM_MODEL_PATH ||
  "/home/pi/litert-lm-models/gemma-4-E2B-it/gemma-4-E2B-it.litertlm";
const litertModelRepo =
  process.env.LITERT_LM_MODEL_REPO ||
  "litert-community/gemma-4-E2B-it-litert-lm";
const litertBackend = process.env.LITERT_LM_BACKEND || "cpu";
const litertEnableSpeculativeDecoding =
  process.env.LITERT_LM_ENABLE_SPECULATIVE_DECODING || "auto";
const litertCacheDir =
  process.env.LITERT_LM_CACHE_DIR || "/tmp/litert-lm-cache";
const litertMaxMessagesLength = parseInt(
  process.env.LITERT_LM_MAX_MESSAGES_LENGTH || "8",
  10,
);
const llmServer = (process.env.LLM_SERVER || "").trim().toLowerCase();
const localHosts = new Set(["127.0.0.1", "localhost", "0.0.0.0"]);
const litertEndpoint = `http://${litertHost}:${litertPort}`;

const chatHistoryFileName = `litert_lm_chat_history_${moment().format(
  "YYYY-MM-DD_HH-mm-ss",
)}.json`;

const messages: Message[] = [
  {
    role: "system",
    content: systemPrompt,
  },
];

let pyProcess: ChildProcess | null = null;
let serverReadyPromise: Promise<void> | null = null;

const isLocalService = localHosts.has(litertHost);

const resetChatHistory = (): void => {
  messages.length = 0;
  messages.push({
    role: "system",
    content: systemPrompt,
  });
};

const delay = async (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

const startLiteRtServer = (): void => {
  if (pyProcess || !isLocalService || llmServer !== "litert-lm") {
    return;
  }

  const scriptPath = path.resolve(
    __dirname,
    "../../../python/litert_lm_server.py",
  );

  console.log("Starting LiteRT-LM server at port", litertPort);
  pyProcess = spawn("python3", [scriptPath], {
    detached: true,
    stdio: "inherit",
    env: {
      ...process.env,
      LITERT_LM_HOST: litertHost,
      LITERT_LM_PORT: litertPort,
      LITERT_LM_MODEL_PATH: litertModelPath,
      LITERT_LM_MODEL_REPO: litertModelRepo,
      LITERT_LM_BACKEND: litertBackend,
      LITERT_LM_ENABLE_SPECULATIVE_DECODING: litertEnableSpeculativeDecoding,
      LITERT_LM_CACHE_DIR: litertCacheDir,
    },
  });

  pyProcess.on("error", (error) => {
    console.error("Failed to start LiteRT-LM server:", error);
  });
};

const ensureLiteRtServerReady = async (): Promise<void> => {
  if (!isLocalService) {
    return;
  }

  if (!serverReadyPromise) {
    serverReadyPromise = (async () => {
      startLiteRtServer();
      for (let attempt = 0; attempt < 30; attempt += 1) {
        try {
          await axios.get(`${litertEndpoint}/health`, { timeout: 1000 });
          return;
        } catch {
          await delay(1000);
        }
      }
      throw new Error(
        `LiteRT-LM server did not become ready at ${litertEndpoint}`,
      );
    })();
  }

  return serverReadyPromise;
};

const trimHistory = (): void => {
  if (litertMaxMessagesLength > 0 && messages.length > litertMaxMessagesLength + 1) {
    const firstSystemMessage = messages[0];
    const restMessages = messages.slice(1);
    const trimmed = restMessages.slice(-litertMaxMessagesLength);
    messages.length = 0;
    messages.push(firstSystemMessage, ...trimmed);
  }
};

const chatWithLLMStream: ChatWithLLMStreamFunction = async (
  inputMessages: Message[] = [],
  partialCallback: (partialAnswer: string) => void,
  endCallback: () => void,
): Promise<void> => {
  if (shouldResetChatHistory()) {
    resetChatHistory();
  }
  updateLastMessageTime();
  let endResolve: () => void = () => {};
  const promise = new Promise<void>((resolve) => {
    endResolve = resolve;
  }).finally(() => {
    fs.writeFileSync(
      path.join(chatHistoryDir, chatHistoryFileName),
      JSON.stringify(messages, null, 2),
    );
  });

  messages.push(...inputMessages);
  trimHistory();

  let partialAnswer = "";
  try {
    await ensureLiteRtServerReady();
    const response = await axios.post(
      `${litertEndpoint}/chat`,
      {
        messages,
      },
      {
        responseType: "stream",
        timeout: 0,
      },
    );

    let buffer = "";
    response.data.on("data", (chunk: Buffer) => {
      buffer += chunk.toString();
      let newlineIndex = buffer.indexOf("\n");

      while (newlineIndex !== -1) {
        const line = buffer.slice(0, newlineIndex).trim();
        buffer = buffer.slice(newlineIndex + 1);
        newlineIndex = buffer.indexOf("\n");

        if (!line) {
          continue;
        }

        try {
          const parsed = JSON.parse(line);
          if (parsed.error) {
            console.error("LiteRT-LM bridge error:", parsed.error);
            continue;
          }
          if (parsed.content) {
            partialCallback(parsed.content);
            partialAnswer += parsed.content;
          }
        } catch (error) {
          console.error("Error parsing LiteRT-LM stream line:", error, line);
        }
      }
    });

    response.data.on("end", () => {
      messages.push({
        role: "assistant",
        content: partialAnswer,
      });
      endResolve();
      endCallback();
    });
  } catch (error: any) {
    console.error("Error during LiteRT-LM chat request:", error.message);
    endResolve();
    endCallback();
  }

  return promise;
};

const summaryTextWithLLM: SummaryTextWithLLMFunction = async (
  text: string,
  promptPrefix: string,
): Promise<string> => {
  await ensureLiteRtServerReady();
  const prompt = `${promptPrefix}\n\n${text}\n\n`;
  const response = await axios.post(`${litertEndpoint}/generate`, {
    prompt,
  });
  return response.data?.text || "";
};

function cleanup() {
  if (pyProcess && !pyProcess.killed) {
    console.log("Killing LiteRT-LM python server...");
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

export default { chatWithLLMStream, resetChatHistory, summaryTextWithLLM };