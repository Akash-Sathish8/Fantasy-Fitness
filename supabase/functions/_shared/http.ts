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

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return json(
      { error: { code: error.code, message: error.message } },
      error.status,
    );
  }
  // Log the type and message only, never request bodies or URLs (USDA's key is in its URL).
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
