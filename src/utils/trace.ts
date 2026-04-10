const traceEnabled = process.env.WHISPLAY_TRACE_EVENTS === "true";

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