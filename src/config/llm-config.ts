require("dotenv").config();

const baseSystemPrompt =
  process.env.ASSISTANT_SYSTEM_PROMPT ||
  process.env.SYSTEM_PROMPT ||
  "You are a local voice assistant running on a Raspberry Pi. Give direct, useful answers. Keep replies short, concrete, and accurate. If you are unsure, say so plainly instead of guessing. Do not roleplay or add emojis unless the user asks for that style.";

const wakeWordEnabled =
  (process.env.WAKE_WORD_ENABLED || "").toLowerCase() === "true";

const wakeWordConversationToolPrompt = wakeWordEnabled
  ? " If the endConversation tool is available and the user clearly wants to end the current conversation, call that tool before giving your brief final reply."
  : "";

// default 5 minutes
export const CHAT_HISTORY_RESET_TIME = parseInt(process.env.CHAT_HISTORY_RESET_TIME || "300" , 10) * 1000; // convert to milliseconds

export let lastMessageTime = 0;

export const updateLastMessageTime = (): void => {
  lastMessageTime = Date.now();
}

export const shouldResetChatHistory = (): boolean => {
  return Date.now() - lastMessageTime > CHAT_HISTORY_RESET_TIME;
}

export const systemPrompt = `${baseSystemPrompt}${wakeWordConversationToolPrompt}`;

