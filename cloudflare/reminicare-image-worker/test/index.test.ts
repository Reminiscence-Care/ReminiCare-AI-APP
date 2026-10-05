import { describe, expect, it, vi } from "vitest";
import { handleRequest, type Env } from "../src/index";

function environment(image = "aW1hZ2U="): Env {
  return {
    APP_API_TOKEN: "app-secret",
    AI: { run: vi.fn(async () => ({ image })) } as unknown as Ai,
    IMAGE_RATE_LIMITER: { limit: vi.fn(async () => ({ success: true })) },
  };
}

function request(path: string, body: object, token = "app-secret") {
  return new Request(`https://worker.test${path}`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("ReminiCare image worker", () => {
  it("exposes a health endpoint without secrets", async () => {
    const response = await handleRequest(new Request("https://worker.test/health"), environment());
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ status: "ok" });
  });

  it("rejects an invalid app token", async () => {
    const response = await handleRequest(request("/v1/images/generations", { prompt: "Taiwan" }, "wrong"), environment());
    expect(response.status).toBe(401);
  });

  it("returns an OpenAI-shaped generation response", async () => {
    const env = environment();
    const response = await handleRequest(request("/v1/images/generations", { prompt: "1960s Taiwan", width: 1024, height: 640 }), env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ data: [{ b64_json: "aW1hZ2U=" }] });
    expect(env.AI.run).toHaveBeenCalledOnce();
  });

  it("accepts a reference image for editing", async () => {
    const env = environment();
    const response = await handleRequest(request("/v1/images/edits", { prompt: "keep composition", imageBase64: "aW1hZ2U=", imageMimeType: "image/jpeg" }), env);
    expect(response.status).toBe(200);
    expect(env.AI.run).toHaveBeenCalledOnce();
  });

  it("maps rate limiting before running the model", async () => {
    const env = environment();
    env.IMAGE_RATE_LIMITER.limit = vi.fn(async () => ({ success: false }));
    const response = await handleRequest(request("/v1/images/generations", { prompt: "Taiwan" }), env);
    expect(response.status).toBe(429);
    expect(env.AI.run).not.toHaveBeenCalled();
  });

  it.each([null, [], { prompt: "" }, { prompt: "Taiwan", width: 10 }])("rejects invalid payload %j", async (payload) => {
    const env = environment();
    const response = await handleRequest(request("/v1/images/generations", payload as object), env);
    expect(response.status).toBe(400);
    expect(env.AI.run).not.toHaveBeenCalled();
  });

  it("rejects oversized bodies without a content-length header", async () => {
    const env = environment();
    const response = await handleRequest(request("/v1/images/generations", { prompt: "x".repeat(4 * 1024 * 1024) }), env);
    expect(response.status).toBe(413);
    expect(env.AI.run).not.toHaveBeenCalled();
  });

  it("serializes multipart dimensions and the reference image", async () => {
    const env = environment();
    let form: FormData | undefined;
    env.AI.run = vi.fn(async (_model, input) => {
      const multipart = (input as { multipart: { body: ReadableStream; contentType: string } }).multipart;
      form = await new Response(multipart.body, { headers: { "content-type": multipart.contentType } }).formData();
      return { image: "aW1hZ2U=" };
    }) as unknown as Ai["run"];
    const response = await handleRequest(request("/v1/images/edits", { prompt: "keep composition", imageBase64: "aW1hZ2U=", imageMimeType: "image/jpeg" }), env);
    expect(response.status).toBe(200);
    expect(form!.get("width")).toBe("1024");
    expect(form!.get("height")).toBe("640");
    expect(form!.get("input_image_0")).toBeInstanceOf(Blob);
  });

  it("hides upstream diagnostics", async () => {
    const env = environment();
    env.AI.run = vi.fn(async () => { throw new Error("sensitive upstream diagnostic"); }) as unknown as Ai["run"];
    const response = await handleRequest(request("/v1/images/generations", { prompt: "Taiwan" }), env);
    expect(response.status).toBe(502);
    expect(await response.text()).not.toContain("sensitive upstream diagnostic");
  });

  it("maps upstream quota errors to 429", async () => {
    const env = environment();
    env.AI.run = vi.fn(async () => { throw new Error("daily neuron limit exceeded"); }) as unknown as Ai["run"];
    const response = await handleRequest(request("/v1/images/generations", { prompt: "Taiwan" }), env);
    expect(response.status).toBe(429);
  });
});
