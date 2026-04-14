import fs from "fs";
import dotenv from "dotenv";
import { protos, SpeechClient } from "@google-cloud/speech";
import {
  googleCloudClientOptions,
  googleCloudCredentialsPath,
  normalizeGoogleLanguageCode,
} from "./common";

dotenv.config();

const googleCloudASRLanguageCode = normalizeGoogleLanguageCode(
  process.env.GOOGLE_CLOUD_ASR_LANGUAGE_CODE || process.env.FASTER_WHISPER_LANGUAGE,
  "en-US",
);
const googleCloudASRModel = (process.env.GOOGLE_CLOUD_ASR_MODEL || "").trim();

const speechClient = new SpeechClient(googleCloudClientOptions);

const formatGoogleCloudASRError = (error: unknown): string => {
  const message = error instanceof Error ? error.message : String(error);
  const lowered = message.toLowerCase();

  if (lowered.includes("speech-to-text api has not been used") || lowered.includes("service_disabled")) {
    return "Google Cloud Speech-to-Text API is disabled for this project. Enable speech.googleapis.com in Google Cloud and try again.";
  }

  if (lowered.includes("could not load the default credentials") || lowered.includes("credentials")) {
    return "Google Cloud ASR credentials are invalid or missing. Check GOOGLE_APPLICATION_CREDENTIALS / GOOGLE_CLOUD_CREDENTIALS_PATH.";
  }

  if (lowered.includes("permission_denied")) {
    return "Google Cloud ASR permission denied. Check that the service account has Speech-to-Text access.";
  }

  return message;
};

const getRecognitionConfig = (
  audioFilePath: string,
): protos.google.cloud.speech.v1.IRecognitionConfig => {
  const extension = audioFilePath.split(".").pop()?.toLowerCase();
  const config: protos.google.cloud.speech.v1.IRecognitionConfig = {
    languageCode: googleCloudASRLanguageCode,
    enableAutomaticPunctuation: true,
    audioChannelCount: 1,
    sampleRateHertz: 16000,
  };

  if (googleCloudASRModel) {
    config.model = googleCloudASRModel;
  }

  if (extension === "mp3") {
    config.encoding = protos.google.cloud.speech.v1.RecognitionConfig.AudioEncoding.MP3;
    delete config.sampleRateHertz;
  } else if (extension === "flac") {
    config.encoding = protos.google.cloud.speech.v1.RecognitionConfig.AudioEncoding.FLAC;
    delete config.sampleRateHertz;
  } else if (extension === "wav") {
    config.encoding = protos.google.cloud.speech.v1.RecognitionConfig.AudioEncoding.LINEAR16;
  }

  return config;
};

export const recognizeAudio = async (
  audioFilePath: string,
): Promise<string> => {
  if (!googleCloudCredentialsPath) {
    throw new Error(
      "Google Cloud credentials path is not set. Use GOOGLE_APPLICATION_CREDENTIALS or GOOGLE_CLOUD_CREDENTIALS_PATH.",
    );
  }
  if (!fs.existsSync(audioFilePath)) {
    throw new Error(`Audio file does not exist: ${audioFilePath}`);
  }

  try {
    const audioBytes = fs.readFileSync(audioFilePath).toString("base64");
    const [response] = await speechClient.recognize({
      audio: { content: audioBytes },
      config: getRecognitionConfig(audioFilePath),
    });
    return (response.results || [])
      .map((result) => result.alternatives?.[0]?.transcript || "")
      .join(" ")
      .trim();
  } catch (error) {
    const friendlyMessage = formatGoogleCloudASRError(error);
    console.error("Google Cloud ASR failed:", friendlyMessage);
    throw new Error(friendlyMessage);
  }
};