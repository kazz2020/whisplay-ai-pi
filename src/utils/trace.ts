const traceEnabled = process.env.WHISPLAY_TRACE_EVENTS === "true";

type LatencyMark = {
  name: string;
  elapsedMs: number;
  details?: unknown;
};

export interface LatencyTrace {
  mark: (name: string, details?: unknown) => void;
  finish: (status: string, details?: unknown) => void;
}

const stringifyTraceDetails = (details: unknown): string => {
  if (details === undefined) {
    return "";
  }

  try {
    const serialized = JSON.stringify(details);
    if (!serialized) {
      return "";
    }
    return serialized.length > 600
      ? `${serialized.slice(0, 597)}...`
      : serialized;
  } catch {
    return String(details);
  }
};

export const isTraceEnabled = (): boolean => traceEnabled;

export const traceEvent = (
  scope: string,
  message: string,
  details?: unknown,
): void => {
  if (!traceEnabled) {
    return;
  }

  const suffix = stringifyTraceDetails(details);
  console.log(
    suffix
      ? `[Trace:${scope}] ${message} ${suffix}`
      : `[Trace:${scope}] ${message}`,
  );
};

export const createLatencyTrace = (
  scope: string,
  label: string,
  details?: unknown,
): LatencyTrace => {
  const startedAt = Date.now();
  const marks: LatencyMark[] = [];
  let finished = false;

  traceEvent(scope, `${label}:start`, details);

  return {
    mark: (name: string, markDetails?: unknown) => {
      if (finished) {
        return;
      }

      const elapsedMs = Date.now() - startedAt;
      const payload = markDetails === undefined
        ? { elapsedMs }
        : { elapsedMs, details: markDetails };
      marks.push({ name, elapsedMs, details: markDetails });
      traceEvent(scope, `${label}:${name}`, payload);
    },
    finish: (status: string, finishDetails?: unknown) => {
      if (finished) {
        return;
      }
      finished = true;

      const totalMs = Date.now() - startedAt;
      const summary = marks
        .map((mark, index) => {
          const previousElapsed = index === 0 ? 0 : marks[index - 1].elapsedMs;
          return `${mark.name}=${mark.elapsedMs}ms(+${mark.elapsedMs - previousElapsed}ms)`;
        })
        .join(" ");

      console.log(
        `[Latency:${scope}] ${label} status=${status} total=${totalMs}ms${summary ? ` ${summary}` : ""}`,
      );

      traceEvent(scope, `${label}:finish`, {
        status,
        totalMs,
        marks,
        details: finishDetails,
      });
    },
  };
};