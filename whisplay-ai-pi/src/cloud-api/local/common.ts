// Common definitions for local API services
export enum defaultPortMap {
  llamaCpp = 8080,
  ollama = 11434,
  llm8850llm = 8000,
  llm8850whisper = 8801,
  llm8850melotts = 8802,
  fasterWhisper = 8803,
  whisper = 8804,
  piperHttp = 8805,
  llm8850lcm = 8806,
  hailoWhisper = 8807,
  hailoVlm = 8808,
  sherpaOnnxTts = 8809,
}

export const getOllamaHeaders = (): Record<string, string> => {
  const apiKey = process.env.OLLAMA_API_KEY?.trim();

  return apiKey
    ? {
        Authorization: `Bearer ${apiKey}`,
      }
    : {};
};