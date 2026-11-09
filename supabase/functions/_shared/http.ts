// Responses for the Edge Functions. Errors go back as
// {"error": {"code": "...", "message": "..."}}, and the app shows the message as-is, so
// every message is written for the player.

export class HttpError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
    this.name = "HttpError";
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * The request body, refused as soon as it passes maxBytes rather than read whole first,
 * so a huge upload can't fill the function's memory.
 */
export async function readBody(
  req: Request,
  maxBytes: number,
  tooLarge: () => HttpError,
): Promise<Uint8Array> {
  if (Number(req.headers.get("Content-Length")) > maxBytes) throw tooLarge();
  const chunks: Uint8Array[] = [];
  let size = 0;
  if (req.body) {
    for await (const chunk of req.body) {
      size += chunk.length;
      if (size > maxBytes) throw tooLarge();
      chunks.push(chunk);
    }
  }
  const body = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.length;
  }
  return body;
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return json(
      { error: { code: error.code, message: error.message } },
      error.status,
    );
  }
  // Log the type and message only; request bodies hold photos and URLs can hold keys.
  console.error(
    error instanceof Error
      ? `${error.name}: ${error.message}`
      : "Unknown error",
  );
  return json(
    {
      error: {
        code: "server_error",
        message: "The Tavern's food service had a problem. Try again.",
      },
    },
    500,
  );
}

/** Reads a whole-number setting, falling back when it's missing or not a number. */
export function intEnv(name: string, fallback: number): number {
  const value = Number.parseInt(Deno.env.get(name) ?? "", 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}
