import path from "path";
import dotenv from "dotenv";

dotenv.config();

const codeToLocaleMap: Record<string, string> = {
  en: "en-US",
  pl: "pl-PL",
  de: "de-DE",
};

export const googleCloudCredentialsPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ||
  process.env.GOOGLE_CLOUD_CREDENTIALS_PATH ||
  "";

export const googleCloudClientOptions = googleCloudCredentialsPath
  ? { keyFilename: path.resolve(googleCloudCredentialsPath) }
  : {};

export const normalizeGoogleLanguageCode = (
  raw: string | undefined,
  fallback: string,
): string => {
  const normalized = (raw || "").trim();
  if (!normalized) {
    return fallback;
  }
  if (normalized.includes("-")) {
    return normalized;
  }
  return codeToLocaleMap[normalized.toLowerCase()] || normalized;
};