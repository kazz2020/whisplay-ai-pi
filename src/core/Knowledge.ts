import { vectorDB, embedText, summaryTextWithLLM, enableRAG } from "../cloud-api/knowledge";
import fs from "fs";
import { chunkText } from "../utils/knowledge";
import {
  getKnowledgeInputDirs,
  KnowledgeSource,
  listKnowledgeSources,
  loadKnowledgeSourceContent,
} from "../utils/knowledge-ingest";
import { v4 as uuidv4 } from "uuid";
import crypto from "crypto";
import readline from "readline";

const collectionName = "whisplay_knowledge";
const knowledgeScoreThreshold = parseFloat(
  process.env.RAG_KNOWLEDGE_SCORE_THRESHOLD || "0.65",
);
const knowledgeTopK = parseInt(process.env.RAG_KNOWLEDGE_TOP_K || "5", 10);
const knowledgeMaxChunks = parseInt(
  process.env.RAG_KNOWLEDGE_MAX_CHUNKS || "3",
  10,
);
const knowledgeMaxChunksPerSource = parseInt(
  process.env.RAG_KNOWLEDGE_MAX_CHUNKS_PER_SOURCE || "2",
  10,
);
const knowledgeMaxContextChars = parseInt(
  process.env.RAG_KNOWLEDGE_MAX_CONTEXT_CHARS || "1800",
  10,
);
const promptPrefix = process.env.RAG_KNOWLEDGE_SUMMARY_PROMPT_PREFIX || "Please provide a concise summary for the following text in **30 words** or less:";
const enableKnowledgeSummary = (process.env.ENABLE_KNOWLEDGE_SUMMARY || "").toLowerCase() === "true";
const enableKnowledgeAutoIndex =
  (process.env.RAG_AUTO_INDEX_ON_START || "false").toLowerCase() === "true";
const knowledgeAutoIndexIntervalMs = Math.max(
  parseInt(process.env.RAG_AUTO_INDEX_INTERVAL_SECONDS || "60", 10) * 1000,
  5000,
);

type IndexKnowledgeOptions = {
  collectionMode?: "auto" | "incremental" | "full";
  deletedSourceStrategy?: "prompt" | "remove" | "keep";
};

type KnowledgeSearchResult = {
  id: number | string;
  score: number;
  payload?:
    | { [key: string]: unknown }
    | Record<string, unknown>
    | undefined
    | null;
};

let isIndexingKnowledge = false;
let knowledgeAutoIndexTimer: NodeJS.Timeout | null = null;
let lastKnowledgeSnapshot = "";

export async function indexKnowledgeCollection(
  options: IndexKnowledgeOptions = {},
) {
  const collectionMode = options.collectionMode || "auto";
  const deletedSourceStrategy = options.deletedSourceStrategy || "prompt";

  if (!enableRAG) {
    console.log(
      "[RAG] RAG is disabled. Skipping knowledge collection creation.",
    );
    return;
  }

  if (isIndexingKnowledge) {
    console.log("[RAG] Knowledge indexing is already in progress. Skipping duplicate request.");
    return;
  }

  isIndexingKnowledge = true;

  try {
    const dimension = await embedText("test").then(
      (embedding) => embedding.length,
    );

    const collections = await vectorDB.getCollections();
    const collectionExists = collections.includes(collectionName);
    let shouldRecreate = false;

    if (collectionExists) {
      const collectionInfo = await vectorDB.getCollection(collectionName);
      const existingDimension = getCollectionVectorSize(collectionInfo);
      if (existingDimension && existingDimension !== dimension) {
        shouldRecreate = await promptYesNo(
          `\nEmbedding dimension mismatch (existing: ${existingDimension}, current: ${dimension}). Full reindex required. Continue? (y/N): `
        );
        if (!shouldRecreate) {
          console.log("Aborted indexing due to dimension mismatch.");
          return;
        }
      } else if (collectionMode === "full") {
        shouldRecreate = true;
      } else if (collectionMode === "incremental") {
        shouldRecreate = false;
      } else {
        const choice = await promptChoice(
          "\nChoose indexing mode: \n\n(i)ncremental \n(f)ull rebuild (WARNING: This operation will delete existing data). \n\n[i]: ",
          "i"
        );
        shouldRecreate = choice === "f";
      }
    } else {
      shouldRecreate = true;
    }

    if (shouldRecreate) {
      if (collectionExists) {
        await vectorDB.deleteCollection(collectionName);
      }
      console.log(`Creating knowledge collection with dimension: ${dimension}`);
      await vectorDB.createCollection(collectionName, dimension, "Cosine");
    }

    const sources = listKnowledgeSources();

    if (!sources.length) {
      console.log(
        `No knowledge files found to index. Checked: ${getKnowledgeInputDirs().join(", ")}`,
      );
    }

    const fileSet = new Set(sources.map((source) => source.source));

    for (const source of sources) {
      const content = loadKnowledgeSourceContent(source);
      if (!content) {
        console.log(`Skipping unreadable or unsupported knowledge file: ${source.source}`);
        continue;
      }

      const fileHash = hashText(content);

      const existingInfo = await getExistingFileInfo(source.source);
      if (existingInfo.exists && existingInfo.hash === fileHash) {
        console.log(`Skipping unchanged file: ${source.source}`);
        continue;
      }

      if (existingInfo.exists) {
        await vectorDB.deletePointsByFilter(
          collectionName,
          buildSourceFilter(source.source),
        );
      }

      const chunks = chunkText(content, 500, 80);
      for (let i = 0; i < chunks.length; i++) {
        const chunk = chunks[i];
        const embedding = await embedText(chunk);
        console.log(
          `Embedding chunk ${i + 1}/${chunks.length} of file ${source.source}`,
        );
        const summary = enableKnowledgeSummary
          ? await summaryTextWithLLM(chunk, promptPrefix)
          : "";
        await vectorDB.upsertPoints(collectionName, [
          {
            id: uuidv4(),
            vector: embedding,
            payload: {
              content: chunk,
              summary,
              source: source.source,
              chunkIndex: i,
              fileHash,
            },
          },
        ]);
      }

      console.log(`Indexed file: ${source.source}`);
    }

    const deletedSources = await getDeletedSources(fileSet);
    if (deletedSources.length > 0) {
      const shouldRemoveDeletedSources = await resolveDeletedSourcesAction(
        deletedSources.length,
        deletedSourceStrategy,
      );
      if (shouldRemoveDeletedSources) {
        for (const source of deletedSources) {
          await vectorDB.deletePointsByFilter(collectionName, buildSourceFilter(source));
          console.log(`Removed knowledge for file: ${source}`);
        }
      }
    }
  } finally {
    isIndexingKnowledge = false;
  }
}

export function startKnowledgeAutoIndexing() {
  if (!enableRAG || !enableKnowledgeAutoIndex) {
    return;
  }

  if (knowledgeAutoIndexTimer) {
    return;
  }

  console.log(
    `[RAG] Auto indexing enabled. Watching ${getKnowledgeInputDirs().join(", ")} every ${Math.floor(
      knowledgeAutoIndexIntervalMs / 1000,
    )}s.`,
  );

  void runKnowledgeAutoIndex("startup");
  knowledgeAutoIndexTimer = setInterval(() => {
    void runKnowledgeAutoIndex("change-detect");
  }, knowledgeAutoIndexIntervalMs);
}

function getCollectionVectorSize(collectionInfo: any): number | null {
  const vectors = collectionInfo?.config?.params?.vectors;
  if (!vectors) {
    return null;
  }
  if (typeof vectors.size === "number") {
    return vectors.size;
  }
  if (typeof vectors === "object") {
    const first = Object.values(vectors)[0] as any;
    if (first && typeof first.size === "number") {
      return first.size;
    }
  }
  return null;
}

function hashText(text: string): string {
  return crypto.createHash("sha256").update(text).digest("hex");
}

function buildSourceFilter(source: string) {
  return {
    must: [
      {
        key: "source",
        match: {
          value: source,
        },
      },
    ],
  };
}

async function getExistingFileInfo(file: string): Promise<{ exists: boolean; hash: string | null }> {
  let offset: number | string | null = null;
  let hasPoints = false;
  let fileHash: string | null = null;

  do {
    const response = await vectorDB.scroll(collectionName, 256, buildSourceFilter(file), offset, true);
    const points = response?.points || [];
    if (points.length > 0) {
      hasPoints = true;
    }
    for (const point of points) {
      const payloadHash = point?.payload?.fileHash;
      if (typeof payloadHash === "string") {
        if (fileHash && fileHash !== payloadHash) {
          return { exists: true, hash: null };
        }
        if (!fileHash) {
          fileHash = payloadHash;
        }
      }
    }
    offset = response?.next_page_offset as any ?? null;
  } while (offset !== null && offset !== undefined);

  return { exists: hasPoints, hash: fileHash };
}

async function getDeletedSources(fileSet: Set<string>): Promise<string[]> {
  const sources = new Set<string>();
  let offset: number | string | null = null;

  do {
    const response = await vectorDB.scroll(collectionName, 512, undefined, offset, true);
    const points = response?.points || [];
    for (const point of points) {
      const source = point?.payload?.source;
      if (typeof source === "string") {
        sources.add(source);
      }
    }
    offset = response?.next_page_offset as number ?? null;
  } while (offset !== null && offset !== undefined);

  return Array.from(sources).filter((source) => !fileSet.has(source));
}

async function resolveDeletedSourcesAction(
  deletedSourceCount: number,
  strategy: "prompt" | "remove" | "keep",
): Promise<boolean> {
  if (strategy === "remove") {
    return true;
  }
  if (strategy === "keep") {
    return false;
  }
  return await promptYesNo(
    `Detected ${deletedSourceCount} removed knowledge files. Remove related knowledge? (y/N): `
  );
}

async function runKnowledgeAutoIndex(reason: string) {
  const currentSnapshot = buildKnowledgeSnapshot();
  if (reason !== "startup" && currentSnapshot === lastKnowledgeSnapshot) {
    return;
  }

  console.log(`[RAG] Starting automatic knowledge indexing (${reason}).`);
  try {
    await indexKnowledgeCollection({
      collectionMode: "incremental",
      deletedSourceStrategy: "remove",
    });
    lastKnowledgeSnapshot = buildKnowledgeSnapshot();
    console.log("[RAG] Automatic knowledge indexing completed.");
  } catch (error) {
    console.error("[RAG] Automatic knowledge indexing failed:", error);
  }
}

function buildKnowledgeSnapshot(): string {
  const sources = listKnowledgeSources();
  if (sources.length === 0) {
    return "";
  }

  return sources.map(serializeKnowledgeSource).join("|");
}

function serializeKnowledgeSource(source: KnowledgeSource): string {
  try {
    const stats = fs.statSync(source.filePath);
    return `${source.source}:${stats.size}:${stats.mtimeMs}`;
  } catch {
    return `${source.source}:missing`;
  }
}

async function promptYesNo(question: string): Promise<boolean> {
  if (!process.stdin.isTTY) {
    console.log("[RAG] Non-interactive environment. Using default: no.");
    return false;
  }
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return await new Promise<boolean>((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      const normalized = answer.trim().toLowerCase();
      resolve(normalized === "y" || normalized === "yes");
    });
  });
}

async function promptChoice(question: string, defaultValue: string): Promise<string> {
  if (!process.stdin.isTTY) {
    console.log("[RAG] Non-interactive environment. Using default choice.");
    return defaultValue;
  }
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return await new Promise<string>((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      const normalized = answer.trim().toLowerCase();
      resolve(normalized || defaultValue);
    });
  });
}

export async function queryKnowledgeBase(query: string, topK: number = 3) {
  const queryEmbedding = await embedText(query);
  const results = await vectorDB.search(collectionName, queryEmbedding, topK);
  return results;
}

export async function retrieveKnowledgeByIds(ids: string[]) {
  return await vectorDB.retrieve(collectionName, ids);
}

function buildKnowledgeContext(results: KnowledgeSearchResult[]): string {
  const sourceChunkCounts = new Map<string, number>();
  const seenKeys = new Set<string>();
  const selected: Array<{
    source: string;
    chunkIndex: number;
    score: number;
    content: string;
  }> = [];
  let totalChars = 0;

  for (const result of results) {
    const payload = (result.payload || {}) as Record<string, unknown>;
    const source = String(payload.source || "knowledge");
    const chunkIndex = Number(payload.chunkIndex || 0);
    const rawSummary = typeof payload.summary === "string" ? payload.summary.trim() : "";
    const rawContent = typeof payload.content === "string" ? payload.content.trim() : "";
    const content = rawSummary || rawContent;

    if (!content) {
      continue;
    }

    const currentPerSource = sourceChunkCounts.get(source) || 0;
    if (currentPerSource >= knowledgeMaxChunksPerSource) {
      continue;
    }

    const dedupeKey = `${source}:${chunkIndex}:${content}`;
    if (seenKeys.has(dedupeKey)) {
      continue;
    }

    const nextChars = totalChars + content.length;
    if (selected.length >= knowledgeMaxChunks || nextChars > knowledgeMaxContextChars) {
      continue;
    }

    seenKeys.add(dedupeKey);
    sourceChunkCounts.set(source, currentPerSource + 1);
    totalChars = nextChars;
    selected.push({
      source,
      chunkIndex,
      score: result.score,
      content,
    });
  }

  if (selected.length === 0) {
    return "";
  }

  const sections = selected.map((item, index) => {
    const score = item.score.toFixed(3);
    return `[Knowledge ${index + 1}]\nSource: ${item.source}\nChunk: ${item.chunkIndex}\nScore: ${score}\nContent: ${item.content}`;
  });

  return [
    "Use the following retrieved knowledge only when it is relevant to the user's request.",
    "Prefer the retrieved facts over guessing. If the knowledge is incomplete, say so plainly.",
    sections.join("\n\n"),
  ].join("\n\n");
}

export async function getSystemPromptWithKnowledge(query: string) {
  let results: KnowledgeSearchResult[] = [];
  try {
    results = await queryKnowledgeBase(query, knowledgeTopK);
  } catch (error) {
    console.error("[RAG] Error querying knowledge base:", error);
    return "";
  }
  if (results.length === 0) {
    console.log("[RAG] No knowledge found.");
    return "";
  }

  const filteredResults = results.filter(
    (result) => result.score >= knowledgeScoreThreshold,
  );
  if (filteredResults.length === 0) {
    console.log("[RAG] Top knowledge score below threshold:", results[0].score);
    return "";
  }

  const knowledgePrompt = buildKnowledgeContext(filteredResults);
  if (!knowledgePrompt) {
    console.log("[RAG] No usable knowledge remained after filtering.");
  }
  return knowledgePrompt;
}
