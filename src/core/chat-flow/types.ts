import { StreamResponser } from "../StreamResponsor";
import { Message } from "../../type";

export type FlowName =
  | "sleep"
  | "camera"
  | "music"
  | "listening"
  | "wake_listening"
  | "asr"
  | "answer"
  | "image"
  | "external_answer";

export type FlowStateHandler = (ctx: ChatFlowContext) => void;

export interface ChatFlowContext {
  currentFlowName: FlowName;
  recordingsDir: string;
  currentRecordFilePath: string;
  asrText: string;
  streamResponser: StreamResponser;
  partialThinking: string;
  thinkingSentences: string[];
  answerId: number;
  enableCamera: boolean;
  knowledgePrompts: string[];
  wakeSessionActive: boolean;
  wakeSessionStartAt: number;
  wakeSessionLastSpeechAt: number;
  wakeSessionIdleTimeoutMs: number;
  wakeRecordMaxSec: number;
  wakeEndKeywords: string[];
  endAfterAnswer: boolean;
  pendingExternalReply: string;
  pendingExternalEmoji: string;
  pendingExternalImageUrl: string;
  currentExternalEmoji: string;
  isFromWakeListening: boolean;
  enterMusicAfterAnswer: boolean;
  musicDisplayText: string;
  conversationMessages: Message[];

  transitionTo: (flowName: FlowName) => void;
  startTurnTrace: (source: string, details?: unknown) => void;
  markTurnTrace: (stage: string, details?: unknown) => void;
  markTurnTraceOnce: (stage: string, details?: unknown) => void;
  finishTurnTrace: (status: string, details?: unknown) => void;
  recognizeAudio: (path: string, isFromAutoListening?: boolean) => Promise<string>;
  partialThinkingCallback: (partialThinking: string) => void;
  startWakeSession: () => void;
  endWakeSession: () => void;
  shouldContinueWakeSession: () => boolean;
  shouldEndAfterAnswer: (text: string) => boolean;
  streamExternalReply: (text: string, emoji?: string) => Promise<void>;
  interruptCurrentAnswer: () => void;
  startResponseInterruptMonitor: (onInterrupt: () => void) => void;
  stopResponseInterruptMonitor: () => void;
  prepareConversationPrompt: (userText: string, knowledgePrompt?: string) => Message[];
  appendPendingAssistantText: (text: string) => void;
  commitPendingAssistantResponse: () => void;
  clearPendingAssistantResponse: () => void;
}
