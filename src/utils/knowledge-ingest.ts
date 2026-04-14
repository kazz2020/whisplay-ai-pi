import fs from "fs";
import path from "path";
import { execFileSync } from "child_process";
import { knowledgeDirs, projectRootDir } from "./dir";

export type KnowledgeSource = {
  filePath: string;
  source: string;
};

const directReadExtensions = new Set([".txt", ".md", ".markdown"]);
const markItDownExtensions = new Set([
  ".pdf",
  ".docx",
  ".doc",
  ".pptx",
  ".ppt",
  ".xlsx",
  ".xls",
  ".csv",
  ".json",
  ".xml",
  ".html",
  ".htm",
  ".epub",
  ".rtf",
  ".jpg",
  ".jpeg",
  ".png",
  ".gif",
  ".webp",
  ".bmp",
  ".tif",
  ".tiff",
]);
const enableMarkItDown =
  (process.env.RAG_MARKITDOWN_ENABLED || "true").toLowerCase() !== "false";

let hasLoggedMarkItDownWarning = false;

export function getKnowledgeInputDirs(): string[] {
  return [...knowledgeDirs];
}

export function listKnowledgeSources(): KnowledgeSource[] {
  const sources: KnowledgeSource[] = [];
  const seenSources = new Set<string>();

  for (const dirPath of knowledgeDirs) {
    collectKnowledgeSources(dirPath, dirPath, sources, seenSources);
  }

  return sources.sort((left, right) => left.source.localeCompare(right.source));
}

export function loadKnowledgeSourceContent(source: KnowledgeSource): string | null {
  const extension = path.extname(source.filePath).toLowerCase();

  if (directReadExtensions.has(extension)) {
    return normalizeContent(fs.readFileSync(source.filePath, "utf-8"));
  }

  if (!enableMarkItDown || !markItDownExtensions.has(extension)) {
    return null;
  }

  const converted = convertWithMarkItDown(source.filePath);
  if (!converted) {
    return null;
  }

  return normalizeContent(converted);
}

function collectKnowledgeSources(
  baseDir: string,
  currentDir: string,
  sources: KnowledgeSource[],
  seenSources: Set<string>,
) {
  const entries = fs.readdirSync(currentDir, { withFileTypes: true });

  for (const entry of entries) {
    if (entry.name.startsWith(".")) {
      continue;
    }

    const entryPath = path.join(currentDir, entry.name);
    if (entry.isDirectory()) {
      collectKnowledgeSources(baseDir, entryPath, sources, seenSources);
      continue;
    }

    if (!entry.isFile()) {
      continue;
    }

    const extension = path.extname(entry.name).toLowerCase();
    if (!directReadExtensions.has(extension) && !markItDownExtensions.has(extension)) {
      continue;
    }

    const relativePath = path.relative(projectRootDir, entryPath).replace(/\\/g, "/");
    if (seenSources.has(relativePath)) {
      continue;
    }

    seenSources.add(relativePath);
    sources.push({
      filePath: entryPath,
      source: relativePath,
    });
  }
}

function convertWithMarkItDown(filePath: string): string | null {
  const scriptPath = path.join(projectRootDir, "python", "markitdown_convert.py");
  const candidates = Array.from(
    new Set(
      [
        process.env.RAG_MARKITDOWN_PYTHON_BIN,
        process.env.PYTHON_BIN,
        process.platform === "win32" ? "python" : "python3",
        process.platform === "win32" ? "py" : "python",
      ].filter((value): value is string => Boolean(value && value.trim()))
    )
  );

  let lastError: unknown = null;

  for (const candidate of candidates) {
    const args = candidate === "py" ? ["-3", scriptPath, filePath] : [scriptPath, filePath];
    try {
      return execFileSync(candidate, args, {
        cwd: projectRootDir,
        encoding: "utf-8",
        maxBuffer: 20 * 1024 * 1024,
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (error) {
      lastError = error;
    }
  }

  if (!hasLoggedMarkItDownWarning) {
    hasLoggedMarkItDownWarning = true;
    console.warn(
      `[RAG] MarkItDown conversion is unavailable. Install it with \"pip install 'markitdown[pdf,docx,pptx,xlsx,xls]'\" or set RAG_MARKITDOWN_ENABLED=false. Last error: ${formatError(lastError)}`,
    );
  }

  return null;
}

function normalizeContent(content: string): string {
  return content.replace(/\u0000/g, "").trim();
}

function formatError(error: unknown): string {
  if (!error) {
    return "unknown error";
  }

  if (error instanceof Error) {
    return error.message;
  }

  return String(error);
}