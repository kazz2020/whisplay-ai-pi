import {
  getCurrentTimeTag,
  getRecordFileDurationMs,
  splitSentences,
} from "./../utils/index";
import { display } from "../device/display";
import { recognizeAudio, resetChatHistory, ttsProcessor } from "../cloud-api/server";
import { isImMode } from "../cloud-api/llm";
import { DEFAULT_EMOJI, extractEmojis } from "../utils";
import { StreamResponser } from "./StreamResponsor";
import { recordingsDir } from "../utils/dir";
import dotEnv from "dotenv";
import { WakeWordListener } from "../device/wakeword";
import { WhisplayIMBridgeServer } from "../device/im-bridge";
import { FlowStateMachine } from "./chat-flow/stateMachine";
import { flowStates } from "./chat-flow/states";
import { ChatFlowContext, FlowName } from "./chat-flow/types";
import { playWakeupChime } from "../device/audio";
import { stopMusicPlayback, isMusicPlaying } from "../device/music-player";
import {
  detectCurrentInputLevel,
  getDynamicVoiceDetectLevel,
} from "../device/voice-detect";
import { shouldResetChatHistory } from "../config/llm-config";
import { Message } from "../type";
import { createLatencyTrace, LatencyTrace } from "../utils/trace";

dotEnv.config();

type AmendmentMode = "add" | "replace" | "refine";

const normalizeWhitespace = (text: string): string =>
  text.replace(/\s+/g, " ").trim();

const trimTrailingPunctuation = (text: string): string =>
  text.replace(/[\s,;:.!?-]+$/g, "").trim();

const uppercaseFirst = (text: string): string =>
  text ? text.charAt(0).toUpperCase() + text.slice(1) : text;

const lowercaseFirst = (text: string): string =>
  text ? text.charAt(0).toLowerCase() + text.slice(1) : text;

const polishAddPrefixes = [
  /^i\s+jeszcze\s+/i,
  /^jeszcze\s+/i,
  /^dodaj\s+(?:jeszcze\s+|też\s+|także\s+)?/i,
  /^dopisz\s+(?:jeszcze\s+|też\s+|także\s+)?/i,
  /^dołóż\s+(?:jeszcze\s+|też\s+|także\s+)?/i,
  /^plus\s+/i,
  /^oraz\s+/i,
  /^i\s+także\s+/i,
  /^dodaj\s+też\s*,?\s*/i,
];

const polishReplacePrefixes = [
  /^czekaj\s*,?\s*/i,
  /^poczekaj\s*,?\s*/i,
  /^chwila\s*,?\s*/i,
  /^stop\s*,?\s*/i,
  /^nie\s*,\s*/i,
  /^a\s+właściwie\s+/i,
  /^właściwie\s+/i,
  /^jednak\s+/i,
  /^raczej\s+/i,
  /^inaczej\s+/i,
  /^zamiast\s+tego\s+/i,
  /^zamiast\s+/i,
  /^lepiej\s+/i,
];

const polishRefinePrefixes = [
  /^tylko\s+/i,
  /^krócej\s+/i,
  /^krótko\s+/i,
  /^na\s+szybko\s*/i,
  /^szybko\s*/i,
  /^punktami\s*/i,
  /^w\s+punktach\s*/i,
  /^formalnie\s*/i,
  /^bardziej\s+formalnie\s*/i,
  /^luźniej\s*/i,
  /^bardziej\s+luźno\s*/i,
  /^po\s+polsku\s*/i,
  /^po\s+angielsku\s*/i,
  /^bardziej\s+krótko\s+/i,
  /^dokładniej\s+/i,
  /^prościej\s+/i,
  /^bardziej\s+technicznie\s*/i,
  /^mniej\s+technicznie\s*/i,
  /^dla\s+dziecka\s*/i,
  /^jak\s+dla\s+dziecka\s*/i,
  /^dla\s+dziecka\s+z\s+podstawówki\s*/i,
  /^jak\s+dla\s+dziecka\s+z\s+podstawówki\s*/i,
  /^dla\s+seniora\s*/i,
  /^w\s+jednym\s+zdaniu\s*/i,
  /^jednym\s+zdaniem\s*/i,
  /^bez\s+tego\s*/i,
  /^bez\s+tego\s+fragmentu\s*/i,
  /^bez\s+przykładów\s*/i,
  /^bez\s+szczegółów\s*/i,
  /^bez\s+technikaliów\s*/i,
];

const englishRefinePrefixes = [
  /^quickly\s*/i,
  /^real\s+quick\s*/i,
  /^briefly\s*/i,
  /^in\s+bullet\s+points\s*/i,
  /^as\s+bullet\s+points\s*/i,
  /^formally\s*/i,
  /^more\s+formally\s*/i,
  /^more\s+casually\s*/i,
  /^casually\s*/i,
  /^for\s+a\s+senior\s*/i,
  /^for\s+a\s+child\s*/i,
  /^for\s+a\s+primary\s+school\s+child\s*/i,
  /^in\s+one\s+sentence\s*/i,
  /^without\s+examples\s*/i,
  /^without\s+details\s*/i,
  /^without\s+technical\s+details\s*/i,
  /^more\s+technical(?:ly)?\s*/i,
  /^less\s+technical(?:ly)?\s*/i,
  /^simpler\s*/i,
  /^more\s+precisely\s*/i,
  /^in\s+polish\s*/i,
  /^in\s+english\s*/i,
];

const polishStyleRefinements: Array<{
  pattern: RegExp;
  build: (base: string, clean: string) => string;
}> = [
  {
    pattern: /^bez\s+tego(?:\s+fragmentu)?$/i,
    build: (base) => `${base}, ale bez tego.`,
  },
  {
    pattern: /^bez\s+(.+)$/i,
    build: (base, clean) => `${base}, ale bez ${clean.replace(/^bez\s+/i, "")}.`,
  },
  {
    pattern: /^bez\s+przykładów$/i,
    build: (base) => `${base}, ale bez przykładów.`,
  },
  {
    pattern: /^(?:bardziej\s+)?technicznie$/i,
    build: (base) => `${base}, wyjaśnij to bardziej technicznie.`,
  },
  {
    pattern: /^mniej\s+technicznie$/i,
    build: (base) => `${base}, wyjaśnij to mniej technicznie.`,
  },
  {
    pattern: /^(?:jak\s+)?dla\s+dziecka$/i,
    build: (base) => `${base}, wyjaśnij to tak, żeby zrozumiało to dziecko.`,
  },
  {
    pattern: /^(?:jak\s+)?dla\s+dziecka\s+z\s+podstawówki$/i,
    build: (base) => `${base}, wyjaśnij to tak, żeby zrozumiało to dziecko z podstawówki.`,
  },
  {
    pattern: /^dla\s+seniora$/i,
    build: (base) => `${base}, wyjaśnij to jasno i spokojnie, z myślą o seniorze.`,
  },
  {
    pattern: /^(?:w\s+jednym\s+zdaniu|jednym\s+zdaniem)$/i,
    build: (base) => `${base}, powiedz to w jednym zdaniu.`,
  },
  {
    pattern: /^krócej$|^krótko$|^bardziej\s+krótko$/i,
    build: (base) => `${base}, ale krócej.`,
  },
  {
    pattern: /^(?:na\s+szybko|szybko)$/i,
    build: (base) => `${base}, ale na szybko.`,
  },
  {
    pattern: /^(?:punktami|w\s+punktach)$/i,
    build: (base) => `${base}, odpowiedz punktami.`,
  },
  {
    pattern: /^(?:formalnie|bardziej\s+formalnie)$/i,
    build: (base) => `${base}, odpowiedz bardziej formalnie.`,
  },
  {
    pattern: /^(?:luźniej|bardziej\s+luźno)$/i,
    build: (base) => `${base}, odpowiedz trochę luźniej.`,
  },
  {
    pattern: /^dokładniej$/i,
    build: (base) => `${base}, ale dokładniej.`,
  },
  {
    pattern: /^prościej$/i,
    build: (base) => `${base}, ale prościej.`,
  },
  {
    pattern: /^po\s+polsku$/i,
    build: (base) => `${base}, odpowiedz po polsku.`,
  },
  {
    pattern: /^po\s+angielsku$/i,
    build: (base) => `${base}, odpowiedz po angielsku.`,
  },
  {
    pattern: /^in\s+one\s+sentence$/i,
    build: (base) => `${base}, answer in one sentence.`,
  },
  {
    pattern: /^in\s+bullet\s+points$|^as\s+bullet\s+points$/i,
    build: (base) => `${base}, answer in bullet points.`,
  },
  {
    pattern: /^formally$|^more\s+formally$/i,
    build: (base) => `${base}, answer more formally.`,
  },
  {
    pattern: /^more\s+casually$|^casually$/i,
    build: (base) => `${base}, answer more casually.`,
  },
  {
    pattern: /^for\s+a\s+senior$/i,
    build: (base) => `${base}, explain it clearly and calmly for a senior.`,
  },
  {
    pattern: /^for\s+a\s+child$/i,
    build: (base) => `${base}, explain it so a child can understand it.`,
  },
  {
    pattern: /^for\s+a\s+primary\s+school\s+child$/i,
    build: (base) => `${base}, explain it so a primary school child can understand it.`,
  },
  {
    pattern: /^without\s+examples$/i,
    build: (base) => `${base}, but without examples.`,
  },
  {
    pattern: /^without\s+details$/i,
    build: (base) => `${base}, but without details.`,
  },
  {
    pattern: /^without\s+technical\s+details$/i,
    build: (base) => `${base}, but without technical details.`,
  },
  {
    pattern: /^more\s+technical(?:ly)?$/i,
    build: (base) => `${base}, explain it in a more technical way.`,
  },
  {
    pattern: /^less\s+technical(?:ly)?$/i,
    build: (base) => `${base}, explain it in a less technical way.`,
  },
  {
    pattern: /^quickly$|^real\s+quick$|^briefly$/i,
    build: (base) => `${base}, but quickly.`,
  },
  {
    pattern: /^simpler$/i,
    build: (base) => `${base}, but simpler.`,
  },
  {
    pattern: /^more\s+precisely$/i,
    build: (base) => `${base}, but more precisely.`,
  },
  {
    pattern: /^in\s+polish$/i,
    build: (base) => `${base}, answer in Polish.`,
  },
  {
    pattern: /^in\s+english$/i,
    build: (base) => `${base}, answer in English.`,
  },
];

const englishAmendmentPrefixes = [
  /^wait\s*,?\s*/i,
  /^actually\s*,?\s*/i,
  /^add\s+/i,
  /^instead\s+/i,
  /^rather\s+/i,
  /^make\s+it\s+/i,
];

const stripFirstMatchingPrefix = (text: string, patterns: RegExp[]): string => {
  let result = text;
  for (const pattern of patterns) {
    result = result.replace(pattern, "");
  }
  return normalizeWhitespace(result);
};

const detectAmendmentMode = (text: string): AmendmentMode => {
  const normalized = normalizeWhitespace(text);
  if (!normalized) {
    return "refine";
  }
  if (polishAddPrefixes.some((pattern) => pattern.test(normalized))) {
    return "add";
  }
  if (polishReplacePrefixes.some((pattern) => pattern.test(normalized))) {
    return "replace";
  }
  if (polishRefinePrefixes.some((pattern) => pattern.test(normalized))) {
    return "refine";
  }
  if (englishRefinePrefixes.some((pattern) => pattern.test(normalized))) {
    return "refine";
  }
  if (englishAmendmentPrefixes.some((pattern) => pattern.test(normalized))) {
    if (/^add\s+/i.test(normalized)) {
      return "add";
    }
    if (/^instead\s+/i.test(normalized)) {
      return "replace";
    }
    return "refine";
  }
  return "refine";
};

const stripAmendmentPrefix = (text: string, mode: AmendmentMode): string => {
  const basePatterns = [...englishAmendmentPrefixes];
  if (mode === "add") {
    return stripFirstMatchingPrefix(text, [...polishAddPrefixes, ...basePatterns]);
  }
  if (mode === "replace") {
    return stripFirstMatchingPrefix(text, [...polishReplacePrefixes, ...basePatterns]);
  }
  return stripFirstMatchingPrefix(text, [...polishRefinePrefixes, ...englishRefinePrefixes, ...polishReplacePrefixes, ...basePatterns]);
};

const mergeInterruptedUserText = (previousText: string, amendmentText: string): string => {
  const previous = normalizeWhitespace(previousText);
  const amendment = normalizeWhitespace(amendmentText);

  if (!previous) {
    return amendment;
  }
  if (!amendment) {
    return previous;
  }

  const mode = detectAmendmentMode(amendment);
  const stripped = stripAmendmentPrefix(amendment, mode) || amendment;
  const base = trimTrailingPunctuation(previous);
  const clean = trimTrailingPunctuation(stripped);
  const normalizedClean = lowercaseFirst(clean);

  if (!clean) {
    return previous;
  }

  if (mode === "add") {
    return `${base}, a dodatkowo ${normalizedClean}.`;
  }

  if (mode === "replace") {
    return `${base}, ale ${normalizedClean}.`;
  }

  const matchedStyleRefinement = polishStyleRefinements.find(({ pattern }) =>
    pattern.test(clean),
  );
  if (matchedStyleRefinement) {
    return matchedStyleRefinement.build(base, clean);
  }

  const shortRefinement = clean.split(" ").length <= 6;
  if (shortRefinement) {
    return `${base}, ${normalizedClean}.`;
  }

  return `${base}. Uwzględnij też, że ${normalizedClean}.`;
};

class ChatFlow implements ChatFlowContext {
  currentFlowName: FlowName = "sleep";
  recordingsDir: string = "";
  currentRecordFilePath: string = "";
  asrText: string = "";
  streamResponser: StreamResponser;
  partialThinking: string = "";
  thinkingSentences: string[] = [];
  answerId: number = 0;
  enableCamera: boolean = false;
  knowledgePrompts: string[] = [];
  wakeWordListener: WakeWordListener | null = null;
  wakeSessionActive: boolean = false;
  wakeSessionStartAt: number = 0;
  wakeSessionLastSpeechAt: number = 0;
  wakeSessionIdleTimeoutMs: number =
    parseInt(process.env.WAKE_WORD_IDLE_TIMEOUT_SEC || "60") * 1000;
  wakeRecordMaxSec: number = parseInt(
    process.env.WAKE_WORD_RECORD_MAX_SEC || "60",
  );
  wakeEndKeywords: string[] = (process.env.WAKE_WORD_END_KEYWORDS || "byebye,goodbye,stop,byebye").toLowerCase()
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter((item) => item.length > 0);
  endAfterAnswer: boolean = false;
  whisplayIMBridge: WhisplayIMBridgeServer | null = null;
  pendingExternalReply: string = "";
  pendingExternalEmoji: string = "";
  pendingExternalImageUrl: string = "";
  currentExternalEmoji: string = "";
  stateMachine: FlowStateMachine;
  isFromWakeListening: boolean = false;
  enterMusicAfterAnswer: boolean = false;
  musicDisplayText: string = "";
  conversationMessages: Message[] = [];
  responseInterruptMonitorStop: () => void = () => {};
  answerInterruptVoiceEnabled: boolean =
    (process.env.ANSWER_INTERRUPT_WITH_VOICE || "true").toLowerCase() ===
    "true";
  answerInterruptGraceMs: number = parseInt(
    process.env.ANSWER_INTERRUPT_GRACE_MS || "1200",
    10,
  );
  answerInterruptPollMs: number = parseInt(
    process.env.ANSWER_INTERRUPT_POLL_MS || "350",
    10,
  );
  answerInterruptConsecutiveDetections: number = parseInt(
    process.env.ANSWER_INTERRUPT_CONSECUTIVE_DETECTIONS || "2",
    10,
  );
  answerInterruptVoiceLevelBoost: number = parseInt(
    process.env.ANSWER_INTERRUPT_VOICE_LEVEL_BOOST || "6",
    10,
  );
  answerInterruptSampleDurationSec: number = parseFloat(
    process.env.ANSWER_INTERRUPT_SAMPLE_DURATION_SEC || "0.18",
  );
  pendingAssistantText: string = "";
  activeUserMessageIndex: number = -1;
  mergeNextInterruptIntoActiveUser: boolean = false;
  currentTurnTrace: LatencyTrace | null = null;
  currentTurnTraceMarks: Set<string> = new Set();

  constructor(options: { enableCamera?: boolean } = {}) {
    console.log(`[${getCurrentTimeTag()}] ChatBot started.`);
    this.recordingsDir = recordingsDir;
    this.stateMachine = new FlowStateMachine(this, flowStates);
    this.streamResponser = new StreamResponser(
      ttsProcessor,
      (sentences: string[]) => {
        if (!this.isAnswerFlow()) return;
        const fullText = sentences.join(" ");
        let emoji = DEFAULT_EMOJI;
        if (this.currentFlowName === "external_answer") {
          emoji = this.currentExternalEmoji || extractEmojis(fullText) || emoji;
        } else {
          emoji = extractEmojis(fullText) || emoji;
        }
        display({
          status: "answering",
          emoji,
          text: fullText,
          RGB: "#0000ff",
          scroll_speed: 3,
        });
      },
      (text: string) => {
        if (!this.isAnswerFlow()) return;
        display({
          status: "answering",
          text: text || undefined,
          scroll_speed: 3,
        });
      },
      ({ charEnd, durationMs }) => {
        if (!this.isAnswerFlow()) return;
        if (!durationMs || durationMs <= 0) return;
        display({
          scroll_sync: {
            char_end: charEnd,
            duration_ms: durationMs,
          },
        });
      },
      (event, payload) => {
        if (event === "tts_enqueued") {
          this.markTurnTraceOnce("tts_enqueued", payload);
          return;
        }
        if (event === "tts_requested") {
          this.markTurnTraceOnce("tts_requested", payload);
          return;
        }
        if (event === "tts_ready") {
          this.markTurnTraceOnce("tts_ready", payload);
          return;
        }
        if (event === "playback_started") {
          this.markTurnTraceOnce("playback_started", payload);
          return;
        }
        if (event === "playback_finished") {
          this.markTurnTraceOnce("playback_finished", payload);
        }
      },
    );
    if (options?.enableCamera) {
      this.enableCamera = true;
    }

    this.transitionTo("sleep");

    const wakeEnabled = (process.env.WAKE_WORD_ENABLED || "").toLowerCase();
    if (wakeEnabled === "true") {
      this.wakeWordListener = new WakeWordListener();
      this.wakeWordListener.on("wake", () => {
        if (this.currentFlowName === "sleep") {
          this.startWakeSession();
        }
      });
      this.wakeWordListener.start();
    }

    if (isImMode) {
      this.whisplayIMBridge = new WhisplayIMBridgeServer();
      this.whisplayIMBridge.on(
        "reply",
        (payload: { reply: string; emoji?: string; imagePath?: string }) => {
          this.pendingExternalReply = payload.reply;
          this.pendingExternalEmoji = payload.emoji || "";
          this.pendingExternalImageUrl = payload.imagePath || "";
          this.transitionTo("external_answer");
        },
      );
      this.whisplayIMBridge.on(
        "status",
        (payload: { status: string; emoji?: string; text?: string; tool?: string }) => {
          const statusText = payload.tool
            ? `[${payload.tool}] ${payload.text || ""}`
            : payload.text || "";
          const statusMap: Record<string, Partial<{ status: string; emoji: string; text: string; RGB: string; scroll_speed: number }>> = {
            thinking: {
              status: "Thinking",
              emoji: payload.emoji || "🤔",
              text: statusText,
              RGB: "#ff6800",
              scroll_speed: 6,
            },
            tool_calling: {
              status: "Tool calling",
              emoji: payload.emoji || "🔧",
              text: statusText,
              RGB: "#ff6800",
              scroll_speed: 4,
            },
            answering: {
              status: "answering...",
              emoji: payload.emoji || "💬",
              RGB: "#00c8a3",
            },
            idle: {
              status: "idle",
              emoji: payload.emoji || "😊",
              RGB: "#000055",
            },
          };
          const displayPayload = statusMap[payload.status] || {
            status: payload.status,
            emoji: payload.emoji || "🤖",
            text: statusText,
            RGB: "#ff6800",
          };
          display(displayPayload);
        },
      );
      this.whisplayIMBridge.start();
    }
  }

  async recognizeAudio(path: string, isFromAutoListening?: boolean): Promise<string> {
    const recordDurationMs = await getRecordFileDurationMs(path);
    if (!isFromAutoListening && recordDurationMs < 500) {
      console.log("Record audio too short, skipping recognition.");
      this.markTurnTrace("asr_skipped_short", { recordDurationMs });
      return Promise.resolve("");
    }
    this.markTurnTrace("asr_started", {
      recordDurationMs,
      isFromAutoListening: Boolean(isFromAutoListening),
    });
    console.time(`[ASR time]`);
    const result = await recognizeAudio(path);
    console.timeEnd(`[ASR time]`);
    this.markTurnTrace("asr_completed", {
      textLength: result.trim().length,
    });
    return result;
  }

  partialThinkingCallback = (partialThinking: string): void => {
    this.partialThinking += partialThinking;
    const { sentences, remaining } = splitSentences(this.partialThinking);
    if (sentences.length > 0) {
      this.thinkingSentences.push(...sentences);
      const displayText = this.thinkingSentences.join(" ");
      display({
        status: "Thinking",
        emoji: "🤔",
        text: displayText,
        RGB: "#ff6800", // yellow
        scroll_speed: 6,
      });
    }
    this.partialThinking = remaining;
  };

  transitionTo = (flowName: FlowName): void => {
    if (flowName !== "answer" && flowName !== "external_answer") {
      this.stopResponseInterruptMonitor();
    }
    if (flowName !== "music" && isMusicPlaying()) {
      stopMusicPlayback();
    }
    console.log(`[${getCurrentTimeTag()}] switch to:`, flowName);
    this.stateMachine.transitionTo(flowName);
  };

  startTurnTrace = (source: string, details?: unknown): void => {
    this.currentTurnTrace?.finish("replaced", { replacedBy: source });
    this.currentTurnTrace = createLatencyTrace("assistant", `turn-${this.answerId}`, {
      source,
      details,
    });
    this.currentTurnTraceMarks.clear();
    this.currentTurnTrace.mark("turn_started", { source });
  };

  markTurnTrace = (stage: string, details?: unknown): void => {
    this.currentTurnTrace?.mark(stage, details);
  };

  markTurnTraceOnce = (stage: string, details?: unknown): void => {
    if (!this.currentTurnTrace || this.currentTurnTraceMarks.has(stage)) {
      return;
    }
    this.currentTurnTraceMarks.add(stage);
    this.currentTurnTrace.mark(stage, details);
  };

  finishTurnTrace = (status: string, details?: unknown): void => {
    this.currentTurnTrace?.finish(status, details);
    this.currentTurnTrace = null;
    this.currentTurnTraceMarks.clear();
  };

  isAnswerFlow = (): boolean => {
    return (
      this.currentFlowName === "answer" ||
      this.currentFlowName === "external_answer"
    );
  };

  streamExternalReply = async (text: string, emoji?: string): Promise<void> => {
    if (!text) {
      this.streamResponser.endPartial();
      return;
    }
    if (emoji) {
      display({
        status: "answering",
        emoji,
        scroll_speed: 3,
      });
    }
    const { sentences, remaining } = splitSentences(text);
    const parts = [...sentences];
    if (remaining.trim()) {
      parts.push(remaining);
    }
    for (const part of parts) {
      this.streamResponser.partial(part);
      await new Promise((resolve) => setTimeout(resolve, 120));
    }
    this.streamResponser.endPartial();
  };

  startWakeSession = (): void => {
    this.wakeSessionActive = true;
    this.wakeSessionStartAt = Date.now();
    this.wakeSessionLastSpeechAt = this.wakeSessionStartAt;
    this.endAfterAnswer = false;
    this.wakeWordListener?.stop();
    playWakeupChime();
    this.transitionTo("wake_listening");
  };

  endWakeSession = (): void => {
    this.wakeSessionActive = false;
    this.endAfterAnswer = false;
    this.wakeWordListener?.start();
  };

  resetConversationMemory = (): void => {
    this.conversationMessages = [];
    this.pendingAssistantText = "";
    this.activeUserMessageIndex = -1;
    this.mergeNextInterruptIntoActiveUser = false;
    resetChatHistory();
  };

  shouldContinueWakeSession = (): boolean => {
    if (!this.wakeSessionActive) return false;
    const last = this.wakeSessionLastSpeechAt || this.wakeSessionStartAt;
    return Date.now() - last < this.wakeSessionIdleTimeoutMs;
  };

  shouldEndAfterAnswer = (text: string): boolean => {
    const lower = text.toLowerCase();
    return this.wakeEndKeywords.some(
      (keyword) => keyword && lower.includes(keyword),
    );
  };

  interruptCurrentAnswer = (): void => {
    this.answerId += 1;
    this.partialThinking = "";
    this.thinkingSentences = [];
    this.stopResponseInterruptMonitor();
    if (this.activeUserMessageIndex >= 0) {
      this.mergeNextInterruptIntoActiveUser = true;
    }
    this.clearPendingAssistantResponse();
    this.finishTurnTrace("interrupted");
    resetChatHistory();
    this.streamResponser.stop();
  };

  prepareConversationPrompt = (
    userText: string,
    knowledgePrompt?: string,
  ): Message[] => {
    if (shouldResetChatHistory()) {
      this.resetConversationMemory();
    }

    const normalizedText = userText.trim();
    if (!normalizedText) {
      return this.conversationMessages.slice();
    }

    if (
      this.mergeNextInterruptIntoActiveUser &&
      this.activeUserMessageIndex >= 0 &&
      this.conversationMessages[this.activeUserMessageIndex]?.role === "user"
    ) {
      const previous = this.conversationMessages[this.activeUserMessageIndex].content.trim();
      this.conversationMessages[this.activeUserMessageIndex].content = mergeInterruptedUserText(
        previous,
        normalizedText,
      );
      this.mergeNextInterruptIntoActiveUser = false;
    } else {
      this.conversationMessages.push({
        role: "user",
        content: uppercaseFirst(normalizedText),
      });
      this.activeUserMessageIndex = this.conversationMessages.length - 1;
      this.mergeNextInterruptIntoActiveUser = false;
    }

    this.pendingAssistantText = "";
    resetChatHistory();

    const prompt: Message[] = this.conversationMessages.map((message) => ({
      role: message.role,
      content: message.content,
    }));

    if (knowledgePrompt) {
      prompt.splice(Math.max(0, prompt.length - 1), 0, {
        role: "system",
        content: knowledgePrompt,
      });
    }

    return prompt;
  };

  appendPendingAssistantText = (text: string): void => {
    this.pendingAssistantText += text;
  };

  commitPendingAssistantResponse = (): void => {
    const finalText = this.pendingAssistantText.trim();
    if (finalText) {
      this.conversationMessages.push({
        role: "assistant",
        content: finalText,
      });
    }
    this.pendingAssistantText = "";
    this.activeUserMessageIndex = -1;
    this.mergeNextInterruptIntoActiveUser = false;
  };

  clearPendingAssistantResponse = (): void => {
    this.pendingAssistantText = "";
  };

  startResponseInterruptMonitor = (onInterrupt: () => void): void => {
    this.stopResponseInterruptMonitor();

    const webAudioEnabled = process.env.WEB_AUDIO_ENABLED === "true";
    if (!this.answerInterruptVoiceEnabled || webAudioEnabled) {
      return;
    }

    let stopped = false;
    let timeoutHandle: NodeJS.Timeout | null = null;
    let consecutiveDetections = 0;
    const startedAt = Date.now();

    const scheduleNext = () => {
      if (stopped) {
        return;
      }
      timeoutHandle = setTimeout(runCheck, this.answerInterruptPollMs);
    };

    const runCheck = async () => {
      if (
        stopped ||
        (this.currentFlowName !== "answer" &&
          this.currentFlowName !== "external_answer")
      ) {
        return;
      }

      if (Date.now() - startedAt < this.answerInterruptGraceMs) {
        scheduleNext();
        return;
      }

      try {
        const baseLevel = await getDynamicVoiceDetectLevel();
        const threshold = Math.min(
          100,
          Math.max(1, baseLevel + this.answerInterruptVoiceLevelBoost),
        );
        const currentLevel = await detectCurrentInputLevel(
          this.answerInterruptSampleDurationSec,
        );

        if (stopped) {
          return;
        }

        if (currentLevel !== null && currentLevel >= threshold) {
          consecutiveDetections += 1;
          if (
            consecutiveDetections >= this.answerInterruptConsecutiveDetections
          ) {
            console.log(
              `[AnswerInterrupt] Voice interruption detected at ${currentLevel}% (threshold ${threshold}%)`,
            );
            onInterrupt();
            return;
          }
        } else {
          consecutiveDetections = 0;
        }
      } catch (error) {
        console.error("[AnswerInterrupt] Voice monitor error:", error);
        consecutiveDetections = 0;
      }

      scheduleNext();
    };

    this.responseInterruptMonitorStop = () => {
      stopped = true;
      if (timeoutHandle) {
        clearTimeout(timeoutHandle);
      }
      timeoutHandle = null;
    };

    scheduleNext();
  };

  stopResponseInterruptMonitor = (): void => {
    this.responseInterruptMonitorStop();
    this.responseInterruptMonitorStop = () => {};
  };
}

export default ChatFlow;
