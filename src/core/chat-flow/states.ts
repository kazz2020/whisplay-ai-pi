import moment from "moment";
import { noop } from "lodash";
import {
  onButtonPressed,
  onButtonReleased,
  onButtonDoubleClick,
  display,
  getCurrentStatus,
  onCameraCapture,
  onTextInput,
  isButtonDown,
} from "../../device/display";
import {
  recordAudio,
  recordAudioManually,
  recordFileFormat,
  getDynamicVoiceDetectLevel,
  stopRecording,
  startThinkingSound,
  stopThinkingSound,
} from "../../device/audio";
import { chatWithLLMStream } from "../../cloud-api/server";
import { isImMode } from "../../cloud-api/llm";
import { getSystemPromptWithKnowledge } from "../Knowledge";
import { enableRAG } from "../../cloud-api/knowledge";
import { cameraDir } from "../../utils/dir";
import {
  clearPendingCapturedImgForChat,
  getLatestGenImg,
  getLatestDisplayImg,
  setLatestCapturedImg,
  setPendingCapturedImgForChat,
} from "../../utils/image";
import { sendWhisplayIMMessage } from "../../cloud-api/whisplay-im/whisplay-im";
import { ChatFlowContext, FlowName, FlowStateHandler } from "./types";
import {
  enterCameraMode,
  handleCameraModePress,
  handleCameraModeRelease,
  onCameraModeExit,
  resetCameraModeControl,
} from "./camera-mode";
import { DEFAULT_EMOJI } from "../../utils";
import { isMusicPlaying, getCurrentTrackTitle, stopMusicPlayback, startPendingMusicPlayback, onMusicTrackChange, onMusicPlaybackEnd } from "../../device/music-player";

const wakeWordVoiceDetectLevelCap = Math.max(
  1,
  parseInt(process.env.WAKE_WORD_VOICE_DETECT_LEVEL_CAP || "24", 10),
);

export const flowStates: Record<FlowName, FlowStateHandler> = {
  sleep: (ctx: ChatFlowContext) => {
    const currentText = getCurrentStatus().text || "";
    onButtonPressed(() => {
      resetCameraModeControl();
      // Stop any playing music when waking up
      stopMusicPlayback();
      ctx.transitionTo("listening");
    });
    onButtonReleased(noop);
    onCameraModeExit(null);
    onTextInput((text: string) => {
      if (ctx.currentFlowName !== "sleep") return;
      ctx.answerId += 1;
      ctx.asrText = text;
      display({ status: "recognizing", text });
      ctx.transitionTo("answer");
    });
    if (ctx.enableCamera) {
      const captureImgPath = `${cameraDir}/capture-${moment().format(
        "YYYYMMDD-HHmmss",
      )}.jpg`;
      onButtonDoubleClick(() => {
        enterCameraMode(captureImgPath);
        ctx.transitionTo("camera");
      });
    }
    display({
      status: "idle",
      emoji: "😴",
      RGB: "#000055",
      rag_icon_visible: false,
      ...(currentText.endsWith("Listening...") || !currentText
        ? {
          text: `Long Press the button to say something${ctx.enableCamera ? ",\ndouble click to launch camera" : ""
            }.`,
        }
        : {}),
    });
  },
  camera: (ctx: ChatFlowContext) => {
    onButtonDoubleClick(null);
    onButtonPressed(() => {
      handleCameraModePress();
    });
    onButtonReleased(() => {
      handleCameraModeRelease();
    });
    onCameraCapture(() => {
      const captureImagePath = getCurrentStatus().capture_image_path;
      if (!captureImagePath) {
        return;
      }
      setLatestCapturedImg(captureImagePath);
      setPendingCapturedImgForChat(captureImagePath);
      display({ image_icon_visible: true });
    });
    onCameraModeExit(() => {
      if (ctx.currentFlowName === "camera") {
        ctx.transitionTo("sleep");
      }
    });
    display({
      status: "camera",
      emoji: "📷",
      RGB: "#00ff88",
    });
  },
  music: (ctx: ChatFlowContext) => {
    // Start deferred music playback when entering music state
    startPendingMusicPlayback();

    // Update display when track changes during continuous playback
    onMusicTrackChange((title) => {
      if (ctx.currentFlowName === "music") {
        display({ text: `Now playing: ${title}` });
      }
    });

    // Return to sleep when non-continuous playback finishes
    onMusicPlaybackEnd(() => {
      if (ctx.currentFlowName === "music") {
        onMusicTrackChange(null);
        onMusicPlaybackEnd(null);
        ctx.transitionTo("sleep");
      }
    });

    onButtonDoubleClick(null);
    onButtonPressed(() => {
      // Stop music immediately when button is pressed
      onMusicTrackChange(null);
      onMusicPlaybackEnd(null);
      stopMusicPlayback();
      ctx.transitionTo("listening");
    });
    onButtonReleased(noop);

    const trackTitle = getCurrentTrackTitle();
    display({
      status: "music",
      emoji: "🎹",
      RGB: "#0066aa",
      text:
        ctx.musicDisplayText ||
        (isMusicPlaying() && trackTitle
          ? `Now playing: ${trackTitle}`
          : "Music mode. Press the button to talk."),
      rag_icon_visible: false,
    });
  },
  listening: (ctx: ChatFlowContext) => {
    ctx.enterMusicAfterAnswer = false;
    ctx.musicDisplayText = "";
    ctx.isFromWakeListening = false;
    ctx.answerId += 1;
    ctx.wakeSessionActive = false;
    ctx.endAfterAnswer = false;
    onButtonDoubleClick(null);
    ctx.currentRecordFilePath = `${ctx.recordingsDir
      }/user-${Date.now()}.${recordFileFormat}`;
    ctx.startTurnTrace("button_press", {
      format: recordFileFormat,
      wakeSessionActive: ctx.wakeSessionActive,
    });
    onButtonPressed(noop);
    const listeningStartedAt = Date.now();
    // If button was already released before we entered this state, go back to sleep
    if (!isButtonDown()) {
      console.log("[listening] Button already released, returning to sleep");
      ctx.transitionTo("sleep");
      return;
    }
    const { result, stop } = recordAudioManually(ctx.currentRecordFilePath);
    const handleRelease = () => {
      if (Date.now() - listeningStartedAt < 500) {
        // Too short to be meaningful — stop recording and return to sleep
        console.log("[listening] Button released too quickly, returning to sleep");
        ctx.markTurnTrace("recording_cancelled_short", {
          heldMs: Date.now() - listeningStartedAt,
        });
        ctx.finishTurnTrace("cancelled_short");
        stop();
        ctx.transitionTo("sleep");
        return;
      }
      ctx.markTurnTrace("recording_stop_requested", {
        heldMs: Date.now() - listeningStartedAt,
      });
      stop();
      display({
        RGB: "#ff6800",
        image: "",
      });
    };
    onButtonReleased(handleRelease);
    ctx.markTurnTrace("recording_started", { mode: "manual" });
    result
      .then(() => {
        ctx.markTurnTrace("recording_finished", { mode: "manual" });
        ctx.transitionTo("asr");
      })
      .catch((err) => {
        console.error("Error during recording:", err);
        ctx.finishTurnTrace("recording_error", {
          message: err instanceof Error ? err.message : String(err),
        });
        ctx.transitionTo("sleep");
      });
    display({
      status: "listening",
      emoji: DEFAULT_EMOJI,
      RGB: "#00ff00",
      text: "Listening...",
      rag_icon_visible: false,
    });
  },
  wake_listening: (ctx: ChatFlowContext) => {
    ctx.enterMusicAfterAnswer = false;
    ctx.musicDisplayText = "";
    ctx.isFromWakeListening = true;
    ctx.answerId += 1;
    const idleDeadline =
      (ctx.wakeSessionLastSpeechAt || ctx.wakeSessionStartAt || Date.now()) +
      ctx.wakeSessionIdleTimeoutMs;
    const remainingIdleMs = idleDeadline - Date.now();

    if (remainingIdleMs <= 0) {
      ctx.endWakeSession();
      ctx.transitionTo("sleep");
      return;
    }

    ctx.currentRecordFilePath = `${ctx.recordingsDir
      }/user-${Date.now()}.${recordFileFormat}`;
    ctx.startTurnTrace("wake_word", {
      format: recordFileFormat,
      remainingIdleMs,
    });
    onButtonPressed(() => {
      ctx.finishTurnTrace("button_override");
      ctx.transitionTo("listening");
    });
    onButtonReleased(noop);
    display({
      status: "detecting",
      emoji: DEFAULT_EMOJI,
      RGB: "#00ff00",
      text: "Detecting voice level...",
      rag_icon_visible: false,
    });
    getDynamicVoiceDetectLevel().then((level) => {
      const appliedLevel = Math.min(level, wakeWordVoiceDetectLevelCap);
      ctx.markTurnTrace("voice_level_ready", {
        level,
        appliedLevel,
        wakeWordVoiceDetectLevelCap,
      });
      let idleTimeoutHandle: NodeJS.Timeout | null = setTimeout(() => {
        idleTimeoutHandle = null;
        if (ctx.currentFlowName !== "wake_listening") {
          return;
        }
        console.log("[wakeword] Wake session idle timeout reached, returning to sleep");
        ctx.finishTurnTrace("wake_idle_timeout");
        ctx.endWakeSession();
        stopRecording();
        ctx.transitionTo("sleep");
      }, remainingIdleMs);

      const clearIdleTimeout = () => {
        if (idleTimeoutHandle) {
          clearTimeout(idleTimeoutHandle);
          idleTimeoutHandle = null;
        }
      };

      display({
        status: "listening",
        emoji: DEFAULT_EMOJI,
        RGB: "#00ff00",
        text: `(Detect level: ${appliedLevel}%) Listening...`,
        rag_icon_visible: false,
      });
      ctx.markTurnTrace("recording_started", {
        mode: "wake",
        voiceDetectLevel: appliedLevel,
      });
      recordAudio(ctx.currentRecordFilePath, ctx.wakeRecordMaxSec, appliedLevel)
        .then(() => {
          clearIdleTimeout();
          if (ctx.currentFlowName !== "wake_listening") {
            return;
          }
          ctx.markTurnTrace("recording_finished", { mode: "wake" });
          ctx.transitionTo("asr");
        })
        .catch((err) => {
          clearIdleTimeout();
          if (ctx.currentFlowName !== "wake_listening") {
            return;
          }
          console.error("Error during auto recording:", err);
          ctx.finishTurnTrace("recording_error", {
            message: err instanceof Error ? err.message : String(err),
          });
          ctx.endWakeSession();
          ctx.transitionTo("sleep");
        });
    });
  },
  asr: (ctx: ChatFlowContext) => {
    display({
      status: "recognizing",
    });
    onButtonDoubleClick(null);
    Promise.race([
      ctx.recognizeAudio(ctx.currentRecordFilePath, ctx.isFromWakeListening),
      new Promise<string>((resolve) => {
        onButtonPressed(() => {
          resolve("[UserPress]");
        });
        onButtonReleased(noop);
      }),
    ]).then((result) => {
      if (ctx.currentFlowName !== "asr") return;
      if (result === "[UserPress]") {
        ctx.finishTurnTrace("interrupted_during_asr");
        ctx.transitionTo("listening");
        return;
      }
      if (result) {
        console.log("Audio recognized result:", result);
        ctx.asrText = result;
        ctx.endAfterAnswer = ctx.shouldEndAfterAnswer(result);
        if (ctx.wakeSessionActive) {
          ctx.wakeSessionLastSpeechAt = Date.now();
        }
        display({ status: "recognizing", text: result });
        ctx.transitionTo("answer");
        return;
      }
      ctx.finishTurnTrace("no_speech");
      if (ctx.wakeSessionActive) {
        if (ctx.shouldContinueWakeSession()) {
          ctx.transitionTo("wake_listening");
        } else {
          ctx.endWakeSession();
          ctx.transitionTo("sleep");
        }
        return;
      }
      ctx.transitionTo("sleep");
    }).catch((error) => {
      if (ctx.currentFlowName !== "asr") return;
      const message = error instanceof Error ? error.message : String(error);
      console.error("ASR pipeline failed:", message);
      ctx.finishTurnTrace("asr_error", { message });
      display({
        status: "error",
        emoji: "⚠️",
        text: message,
      });
      if (ctx.wakeSessionActive) {
        ctx.endWakeSession();
      }
      ctx.transitionTo("sleep");
    });
  },
  answer: (ctx: ChatFlowContext) => {
    ctx.enterMusicAfterAnswer = false;
    ctx.musicDisplayText = "";
    stopThinkingSound();
    display({
      status: "answering...",
      RGB: "#00c8a3",
    });
    const currentAnswerId = ctx.answerId;
    ctx.markTurnTrace("answer_started", {
      inputLength: ctx.asrText.length,
    });
    const interruptToListening = () => {
      stopThinkingSound();
      ctx.interruptCurrentAnswer();
      clearPendingCapturedImgForChat();
      display({ image_icon_visible: false });
      ctx.transitionTo("listening");
    };
    if (isImMode) {
      const prompt: {
        role: "system" | "user";
        content: string;
      }[] = [
          {
            role: "user",
            content: ctx.asrText,
          },
        ];
      sendWhisplayIMMessage(prompt)
        .then((ok) => {
          if (ok) {
            display({
              status: "idle",
              emoji: "😊",
              RGB: "#000055",
              image_icon_visible: false,
            });
          } else {
            display({
              status: "error",
              emoji: "⚠️",
              text: "OpenClaw send failed",
              image_icon_visible: false,
            });
          }
        })
        .finally(() => {
          clearPendingCapturedImgForChat();
          ctx.transitionTo("sleep");
        });
      return;
    }
    onButtonPressed(() => {
      interruptToListening();
    });
    onButtonReleased(noop);
    const {
      partial,
      endPartial,
      getPlayEndPromise,
    } = ctx.streamResponser;
    ctx.partialThinking = "";
    ctx.thinkingSentences = [];
    startThinkingSound();
    [() => Promise.resolve().then(() => ""), getSystemPromptWithKnowledge]
    [enableRAG ? 1 : 0](ctx.asrText)
      .then((res: string) => {
        ctx.markTurnTrace("knowledge_ready", {
          hasKnowledge: Boolean(res),
          knowledgeLength: res.length,
        });
        let knowledgePrompt = res;
        if (res) {
          console.log("Retrieved knowledge for RAG:\n", res);
        }
        if (ctx.knowledgePrompts.includes(res)) {
          console.log(
            "[RAG] Knowledge prompt already used in this session, skipping to avoid repetition.",
          );
          knowledgePrompt = "";
        }
        if (knowledgePrompt) {
          ctx.knowledgePrompts.push(knowledgePrompt);
        }
        display({
          rag_icon_visible: Boolean(enableRAG && knowledgePrompt),
        });
        const prompt = ctx.prepareConversationPrompt(
          ctx.asrText,
          knowledgePrompt,
        );
        ctx.markTurnTrace("llm_started", {
          promptMessages: prompt.length,
        });
        chatWithLLMStream(
          prompt,
          (text) => {
            if (currentAnswerId !== ctx.answerId) {
              return;
            }
            stopThinkingSound();
            ctx.markTurnTraceOnce("llm_first_token", {
              chunkLength: text.length,
            });
            ctx.appendPendingAssistantText(text);
            partial(text);
          },
          () => {
            stopThinkingSound();
            ctx.markTurnTrace("llm_completed");
            if (currentAnswerId === ctx.answerId) {
              endPartial();
            }
          },
          (partialThinking) =>
            currentAnswerId === ctx.answerId &&
            ctx.partialThinkingCallback(partialThinking),
          (functionName: string, result?: string) => {
            if (
              functionName === "endConversation" &&
              result?.startsWith("[success]")
            ) {
              ctx.endAfterAnswer = true;
            }
            if (
              functionName === "generateImage" &&
              result?.startsWith("[success]")
            ) {
              const img = getLatestGenImg();
              if (img) {
                display({ image: img });
              }
            }
            if (
              functionName.startsWith("playMusic") &&
              result?.startsWith("[success]")
            ) {
              ctx.enterMusicAfterAnswer = true;
              ctx.musicDisplayText = result.replace(/^\[success\]/, "").trim();
            }
            if (result) {
              display({
                text: `[${functionName}]${result}`,
              });
            } else {
              display({
                text: `Invoking [${functionName}]... {count}s`,
              });
            }
          },
        );
      })
      .catch((err) => {
        stopThinkingSound();
        console.error("Error while preparing answer prompt:", err);
        ctx.finishTurnTrace("answer_prepare_error", {
          message: err instanceof Error ? err.message : String(err),
        });
        ctx.transitionTo("sleep");
      });
    getPlayEndPromise().then(() => {
      stopThinkingSound();
      if (ctx.currentFlowName === "answer" && currentAnswerId === ctx.answerId) {
        const finalAssistantText = ctx.pendingAssistantText.trim();
        if (!finalAssistantText) {
          ctx.finishTurnTrace("llm_empty_response");
          clearPendingCapturedImgForChat();
          display({
            status: "error",
            emoji: "⚠️",
            text: "No answer returned. Check OLLAMA_API_KEY or access to the selected Ollama Cloud model.",
            image_icon_visible: false,
          });
          if (ctx.wakeSessionActive) {
            ctx.endWakeSession();
          }
          ctx.transitionTo("sleep");
          return;
        }
        ctx.finishTurnTrace("completed", {
          enterMusicAfterAnswer: ctx.enterMusicAfterAnswer,
          wakeSessionActive: ctx.wakeSessionActive,
          endAfterAnswer: ctx.endAfterAnswer,
        });
        ctx.commitPendingAssistantResponse();
        clearPendingCapturedImgForChat();
        display({ image_icon_visible: false });
        if (ctx.wakeSessionActive || ctx.endAfterAnswer) {
          if (ctx.endAfterAnswer) {
            ctx.endWakeSession();
            ctx.transitionTo("sleep");
          } else {
            ctx.transitionTo("wake_listening");
          }
          return;
        }
        if (ctx.enterMusicAfterAnswer) {
          ctx.transitionTo("music");
          return;
        }
        const img = getLatestDisplayImg();
        if (img) {
          ctx.transitionTo("image");
        } else {
          ctx.transitionTo("sleep");
        }
      }
    });
    ctx.startResponseInterruptMonitor(interruptToListening);
    onButtonPressed(() => {
      interruptToListening();
    });
    onButtonReleased(noop);
  },
  image: (ctx: ChatFlowContext) => {
    onButtonPressed(() => {
      display({ image: "" });
      ctx.transitionTo("listening");
    });
    onButtonReleased(noop);
  },
  external_answer: (ctx: ChatFlowContext) => {
    if (!ctx.pendingExternalReply && !ctx.pendingExternalImageUrl) {
      ctx.transitionTo("sleep");
      return;
    }
    display({
      status: "answering...",
      RGB: "#00c8a3",
      ...(ctx.pendingExternalEmoji ? { emoji: ctx.pendingExternalEmoji } : {}),
    });
    const currentAnswerId = ctx.answerId;
    const interruptToListening = () => {
      ctx.interruptCurrentAnswer();
      display({ image: "" });
      ctx.transitionTo("listening");
    };
    onButtonPressed(() => {
      interruptToListening();
    });
    onButtonReleased(noop);
    const replyText = ctx.pendingExternalReply;
    const replyEmoji = ctx.pendingExternalEmoji;
    const replyImageUrl = ctx.pendingExternalImageUrl;
    ctx.currentExternalEmoji = replyEmoji;
    ctx.pendingExternalReply = "";
    ctx.pendingExternalEmoji = "";
    ctx.pendingExternalImageUrl = "";

    // Display the image if one was provided
    if (replyImageUrl) {
      display({ image: replyImageUrl });
    }

    if (replyText) {
      ctx.clearPendingAssistantResponse();
      void ctx.streamExternalReply(replyText, replyEmoji);
      ctx.startResponseInterruptMonitor(interruptToListening);
      ctx.streamResponser.getPlayEndPromise().then(() => {
        if (
          ctx.currentFlowName !== "external_answer" ||
          currentAnswerId !== ctx.answerId
        ) {
          return;
        }
        if (ctx.wakeSessionActive || ctx.endAfterAnswer) {
          if (ctx.endAfterAnswer) {
            ctx.endWakeSession();
            ctx.transitionTo("sleep");
          } else {
            ctx.transitionTo("wake_listening");
          }
        } else if (replyImageUrl) {
          // Stay in image display mode after TTS finishes
          ctx.transitionTo("image");
        } else {
          ctx.transitionTo("sleep");
        }
      });
    } else {
      // Image only, no text to speak — go to image display mode
      ctx.transitionTo("image");
    }
  },
};
