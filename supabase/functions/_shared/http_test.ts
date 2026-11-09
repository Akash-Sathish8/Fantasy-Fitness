import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.13";
import { HttpError, readBody } from "./http.ts";

const tooLarge = () => new HttpError(413, "too_large", "Too large.");

function upload(bytes: number, headers: Record<string, string> = {}): Request {
  // A stream, so there's no Content-Length unless the test sets one.
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (let sent = 0; sent < bytes; sent += 1000) {
        controller.enqueue(
          new Uint8Array(Math.min(1000, bytes - sent)).fill(7),
        );
      }
      controller.close();
    },
  });
  return new Request("http://localhost/", { method: "POST", body, headers });
}

Deno.test("reads a body up to the limit", async () => {
  const body = await readBody(upload(2500), 2500, tooLarge);
  assertEquals(body.length, 2500);
  assertEquals(body[2499], 7);
});

Deno.test("refuses a body as soon as it passes the limit", async () => {
  await assertRejects(() => readBody(upload(2501), 2500, tooLarge), HttpError);
});

Deno.test("refuses a declared length over the limit before reading", async () => {
  const req = new Request("http://localhost/", {
    method: "POST",
    body: "x",
    headers: { "Content-Length": "5000000" },
  });
  await assertRejects(() => readBody(req, 2500, tooLarge), HttpError);
});
