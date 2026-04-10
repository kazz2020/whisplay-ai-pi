import { OpenAI, ClientOptions } from "openai";
import dotenv from "dotenv";
import * as fs from "fs";
import * as path from "path";
import { isEmpty } from "lodash";
import moment from "moment";
import {
  shouldResetChatHistory,
  systemPrompt,
  updateLastMessageTime,
} from "../../config/llm-config";
import { FunctionCall, Message } from "../../type";
import { combineFunction } from "../../utils";
import { proxyFetch } from "../proxy-fetch";
import { llmFuncMap, llmTools } from "../../config/llm-tools";
import {
  ChatWithLLMStreamFunction,
  SummaryTextWithLLMFunction,
} from "../interface";
import { chatHistoryDir } from "../../utils/dir";
import {
  consumePendingCapturedImgForChat,
  hasPendingCapturedImgForChat,
  getImageMimeType,
} from "../../utils/image";

dotenv.config();

const llamaCppEndpoint = (
  process.env.LLAMA_CPP_ENDPOINT || "http://127.0.0.1:8080"
).replace(/\/+$/, "");
const llamaCppApiKey = process.env.LLAMA_CPP_API_KEY || "llama-cpp-local";
const llamaCppModel =
  process.env.LLAMA_CPP_MODEL || "qwen2.5-1.5b-instruct";
const llamaCppEnableTools =
  (process.env.LLAMA_CPP_ENABLE_TOOLS || "true").toLowerCase() === "true";
const llamaCppUseStream =
  (process.env.LLAMA_CPP_USE_STREAM || "true").toLowerCase() === "true";
const llamaCppMaxMessagesLength = parseInt(
  process.env.LLAMA_CPP_MAX_MESSAGES_LENGTH || "0",
  10,
);
const useCapturedImageInChat =
  (process.env.USE_CAPTURED_IMAGE_IN_CHAT || "false").toLowerCase() ===
  "true";
const openaiUseImagePath =
  (process.env.OPENAI_USE_IMAGE_PATH || "false").toLowerCase() === "true";

const clientOptions: ClientOptions = {
  apiKey: llamaCppApiKey,
  baseURL: `${llamaCppEndpoint}/v1`,
  fetch: proxyFetch as any,
};

const llamaCppClient = new OpenAI(clientOptions);

const buildImageDataUrl = (imagePath: string): string => {
  const mimeType = getImageMimeType(imagePath) || "image/jpeg";
  const base64 = fs.readFileSync(imagePath).toString("base64");
  return `data:${mimeType};base64,${base64}`;
};

const chatHistoryFileName = `llama_cpp_chat_history_${moment().format(
  "YYYY-MM-DD_HH-mm-ss",
)}.json`;

const messages: Message[] = [
  {
    role: "system",
    content: systemPrompt,
  },
];

const resetChatHistory = (): void => {
  messages.length = 0;
  messages.push({
    role: "system",
    content: systemPrompt,
  });
};

const chatWithLLMStream: ChatWithLLMStreamFunction = async (
  inputMessages: Message[] = [],
  partialCallback: (partial: string) => void,
  endCallback: () => void,
  partialThinkingCallback?: (partialThinking: string) => void,
  invokeFunctionCallback?: (functionName: string, result?: string) => void,
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
  if (llamaCppMaxMessagesLength > 0 && messages.length > llamaCppMaxMessagesLength + 1) {
    const firstSystemMessage = messages[0];
    const restMessages = messages.slice(1);
    const trimmed = restMessages.slice(-llamaCppMaxMessagesLength);
    messages.length = 0;
    messages.push(firstSystemMessage, ...trimmed);
  }

  const lastUserMessage = [...inputMessages]
    .reverse()
    .find((msg) => msg.role === "user");
  const capturedImagePath =
    useCapturedImageInChat && lastUserMessage && hasPendingCapturedImgForChat()
      ? consumePendingCapturedImgForChat()
      : "";
  const multimodalLastUserContent = capturedImagePath
    ? [
        {
          type: "text",
          text: lastUserMessage?.content || "",
        },
        {
          type: "image_url",
          image_url: {
            url: openaiUseImagePath
              ? capturedImagePath
              : buildImageDataUrl(capturedImagePath),
          },
        },
      ]
    : [
        {
          type: "text",
          text: lastUserMessage?.content || "",
        },
      ];

  const lastUserMessageIndex = messages
    .map((msg, index) => ({ msg, index }))
    .filter(({ msg }) => msg.role === "user")
    .map(({ index }) => index)
    .pop();

  const requestMessages = messages.map((msg, index) => {
    if (
      capturedImagePath &&
      msg.role === "user" &&
      lastUserMessageIndex !== undefined &&
      index === lastUserMessageIndex
    ) {
      return {
        role: "user",
        content: multimodalLastUserContent,
      };
    }
    return {
      role: msg.role,
      content: msg.content,
      ...(msg.tool_call_id ? { tool_call_id: msg.tool_call_id } : {}),
      ...(msg.tool_calls ? { tool_calls: msg.tool_calls } : {}),
    };
  });

  let answer = "";
  let functionCalls: FunctionCall[] = [];

  try {
    if (llamaCppUseStream) {
      const chatCompletion = await llamaCppClient.chat.completions.create({
        model: llamaCppModel,
        messages: requestMessages as any,
        stream: true,
        tools: llamaCppEnableTools ? llmTools : undefined,
      });
      let partialAnswer = "";
      let partialThinking = "";
      const functionCallsPackages: any[] = [];
      for await (const chunk of chatCompletion) {
        const delta = chunk.choices[0]?.delta as any;
        if (delta?.content) {
          partialCallback(delta.content);
          partialAnswer += delta.content;
        }
        if (delta?.reasoning_content) {
          partialThinkingCallback?.(delta.reasoning_content);
          partialThinking += delta.reasoning_content;
        }
        if (delta?.tool_calls) {
          functionCallsPackages.push(...delta.tool_calls);
        }
      }
      answer = partialAnswer;
      functionCalls = combineFunction(functionCallsPackages);
      if (partialThinking) {
        console.log("llama.cpp reasoning captured:", partialThinking);
      }
    } else {
      const chatCompletion = await llamaCppClient.chat.completions.create({
        model: llamaCppModel,
        messages: requestMessages as any,
        stream: false,
        tools: llamaCppEnableTools ? llmTools : undefined,
      });
      if (chatCompletion.choices && chatCompletion.choices.length > 0) {
        const msg = chatCompletion.choices[0].message as any;
        answer = msg?.content || "";
        if (msg?.reasoning_content) {
          partialThinkingCallback?.(msg.reasoning_content);
        }
        partialCallback(answer);
        functionCalls = combineFunction((msg?.tool_calls as any) || []);
      }
    }
  } catch (error: any) {
    console.log("Error during llama.cpp chat completion request:", error.message);
    endResolve();
    endCallback();
    return promise;
  }

  messages.push({
    role: "assistant",
    content: answer,
    tool_calls: isEmpty(functionCalls) ? undefined : functionCalls,
  });

  if (!isEmpty(functionCalls)) {
    const results = await Promise.all(
      functionCalls.map(async (call: FunctionCall) => {
        const {
          function: { arguments: argString, name },
          id,
        } = call;
        let args: Record<string, any> = {};
        try {
          args = JSON.parse(argString || "{}");
        } catch {
          console.error(
            `Error parsing arguments for function ${name}:`,
            argString,
          );
        }
        const func = llmFuncMap[name! as string];
        invokeFunctionCallback?.(name! as string);
        if (func) {
          return [
            id,
            await func(args)
              .then((res) => {
                invokeFunctionCallback?.(name! as string, res);
                return res;
              })
              .catch((err) => {
                console.error(`Error executing function ${name}:`, err);
                return `Error executing function ${name}: ${err.message}`;
              }),
          ];
        }
        console.error(`Function ${name} not found`);
        return [id, `Function ${name} not found`];
      }),
    );

    const newMessages: Message[] = results.map(([id, result]: any) => ({
      role: "tool",
      content: result as string,
      tool_call_id: id as string,
    }));

    await chatWithLLMStream(newMessages, partialCallback, () => {
      endResolve();
      endCallback();
    });
    return promise;
  }

  endResolve();
  endCallback();
  return promise;
};

const summaryTextWithLLM: SummaryTextWithLLMFunction = async (
  text: string,
  promptPrefix: string,
): Promise<string> => {
  try {
    const chatCompletion = await llamaCppClient.chat.completions.create({
      model: llamaCppModel,
      messages: [
        {
          role: "system",
          content: promptPrefix,
        },
        {
          role: "user",
          content: text,
        },
      ],
      stream: false,
    });
    if (chatCompletion.choices && chatCompletion.choices.length > 0) {
      const summary = chatCompletion.choices[0].message?.content || "";
      console.log("llama.cpp summary:", summary);
      return summary;
    }
  } catch (error: any) {
    console.log("Error during llama.cpp summary request:", error.message);
  }
  return text;
};

export default { chatWithLLMStream, resetChatHistory, summaryTextWithLLM };
