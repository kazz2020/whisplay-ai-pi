import fs from "fs";
import path from "path";
import dotenv from "dotenv";
import textToSpeech from "@google-cloud/text-to-speech";
import { getAudioDurationInSeconds } from "get-audio-duration";
import { TTSResult } from "../../type";
import { ttsDir } from "../../utils/dir";
import {
  googleCloudClientOptions,
  googleCloudCredentialsPath,
  normalizeGoogleLanguageCode,
} from "./common";

dotenv.config();

const googleCloudTTSLanguageCode = normalizeGoogleLanguageCode(
  process.env.GOOGLE_CLOUD_TTS_LANGUAGE_CODE,
  "en-US",
);
const googleCloudTTSVoiceName = (process.env.GOOGLE_CLOUD_TTS_VOICE_NAME || "").trim();
const googleCloudTTSSsmlGender =
  (process.env.GOOGLE_CLOUD_TTS_SSML_GENDER || "NEUTRAL").toUpperCase() as keyof typeof textToSpeech.protos.google.cloud.texttospeech.v1.SsmlVoiceGender;

const textToSpeechClient = new textToSpeech.TextToSpeechClient(
  googleCloudClientOptions,
);

const googleCloudTTS = async (text: string): Promise<TTSResult> => {
  if (!googleCloudCredentialsPath) {
    console.error(
      "Google Cloud credentials path is not set. Use GOOGLE_APPLICATION_CREDENTIALS or GOOGLE_CLOUD_CREDENTIALS_PATH.",
    );
    return { duration: 0 };
  }

  try {
    const [response] = await textToSpeechClient.synthesizeSpeech({
      input: { text },
      voice: {
        languageCode: googleCloudTTSLanguageCode,
        ...(googleCloudTTSVoiceName ? { name: googleCloudTTSVoiceName } : {}),
        ssmlGender:
          textToSpeech.protos.google.cloud.texttospeech.v1.SsmlVoiceGender[
            googleCloudTTSSsmlGender
          ] || textToSpeech.protos.google.cloud.texttospeech.v1.SsmlVoiceGender.NEUTRAL,
      },
      audioConfig: {
        audioEncoding:
          textToSpeech.protos.google.cloud.texttospeech.v1.AudioEncoding.LINEAR16,
      },
    });

    if (!response.audioContent) {
      console.error("No audio content received from Google Cloud TTS.");
      return { duration: 0 };
    }

    const outputPath = path.join(ttsDir, `google_cloud_tts_${Date.now()}.wav`);
    const buffer =
      typeof response.audioContent === "string"
        ? Buffer.from(response.audioContent, "base64")
        : Buffer.from(response.audioContent);
    fs.writeFileSync(outputPath, buffer);

    return {
      filePath: outputPath,
      duration: (await getAudioDurationInSeconds(outputPath)) * 1000,
    };
  } catch (error) {
    console.error("Google Cloud TTS failed:", error);
    return { duration: 0 };
  }
};

export default googleCloudTTS;