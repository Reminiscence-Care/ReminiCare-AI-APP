const MODEL = "@cf/black-forest-labs/flux-2-klein-4b";
const MAX_BODY_BYTES = 4 * 1024 * 1024;
const MAX_PROMPT_LENGTH = 2400;
const DEFAULT_WIDTH = 1024;
const DEFAULT_HEIGHT = 640;

class ApiError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
  }
}

function invalid(message: string): never {
  throw new ApiError(400, "invalid_request", message);
}

interface RateLimitBinding {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  AI: Ai;
  APP_API_TOKEN: string;
  IMAGE_RATE_LIMITER: RateLimitBinding;
}

interface ImageRequest {
  prompt?: unknown;
  imageBase64?: unknown;
  imageMimeType?: unknown;
  width?: unknown;
  height?: unknown;
}

const json = (body: unknown, status = 200) =>
  Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });

function error(status: number, code: string, message: string) {
  return json({ error: { code, message } }, status);
}

function validToken(request: Request, expected: string): boolean {
  const supplied = request.headers.get("authorization") ?? "";
  const wanted = `Bearer ${expected}`;
  if (!expected || supplied.length !== wanted.length) return false;
  let difference = 0;
  for (let index = 0; index < wanted.length; index++) {
    difference |= supplied.charCodeAt(index) ^ wanted.charCodeAt(index);
  }
  return difference === 0;
}

function dimension(value: unknown, fallback: number): number {
  if (value == null) return fallback;
  if (typeof value !== "number" || !Number.isInteger(value)) {
    invalid("圖片尺寸必須是整數。");
  }
  if (value < 256 || value > 1920 || value % 8 !== 0) {
    invalid("圖片尺寸必須介於 256 到 1920，且為 8 的倍數。");
  }
  return value;
}

function decodeBase64(value: string): Uint8Array {
  const raw = value.includes(",") ? value.substring(value.indexOf(",") + 1) : value;
  if (!raw || raw.length > MAX_BODY_BYTES * 1.4) invalid("輸入圖片過大。");
  try {
    const binary = atob(raw);
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    if (bytes.length === 0 || bytes.length > MAX_BODY_BYTES) invalid("輸入圖片過大。");
    return bytes;
  } catch (cause) {
    if (cause instanceof ApiError) throw cause;
    invalid("輸入圖片不是有效的 Base64。");
  }
}

async function runModel(env: Env, payload: ImageRequest, editing: boolean) {
  if (typeof payload.prompt !== "string" || payload.prompt.trim().length === 0) {
    invalid("提示詞不可空白。");
  }
  const prompt = payload.prompt.trim();
  if (prompt.length > MAX_PROMPT_LENGTH) invalid("提示詞過長。");

  const form = new FormData();
  form.append("prompt", prompt);
  form.append("width", dimension(payload.width, DEFAULT_WIDTH).toString());
  form.append("height", dimension(payload.height, DEFAULT_HEIGHT).toString());
  form.append("guidance", "4");

  if (editing) {
    if (typeof payload.imageBase64 !== "string") invalid("改圖請求缺少原始圖片。");
    if (payload.imageMimeType !== "image/jpeg" && payload.imageMimeType !== "image/png") {
      invalid("輸入圖片必須為 JPEG 或 PNG。");
    }
    const bytes = decodeBase64(payload.imageBase64);
    const mimeType = payload.imageMimeType === "image/jpeg" ? "image/jpeg" : "image/png";
    const imageBuffer = bytes.buffer.slice(
      bytes.byteOffset,
      bytes.byteOffset + bytes.byteLength,
    ) as ArrayBuffer;
    form.append("input_image_0", new Blob([imageBuffer], { type: mimeType }), "memory-reference");
  }

  const serialized = new Response(form);
  let timeout: ReturnType<typeof setTimeout> | undefined;
  const result = (await Promise.race([env.AI.run(MODEL, {
    multipart: {
      body: serialized.body,
      contentType: serialized.headers.get("content-type"),
    },
  } as never), new Promise<never>((_, reject) => {
    timeout = setTimeout(() => reject(new ApiError(504, "timeout", "Cloudflare 圖片模型請求逾時。")), 150000);
  })]).finally(() => clearTimeout(timeout))) as { image?: string };

  if (!result || typeof result.image !== "string" || !result.image) {
    throw new ApiError(502, "invalid_response", "模型沒有回傳圖片資料。");
  }
  return result.image;
}

export async function handleRequest(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/health") {
    return json({ status: "ok", model: MODEL, version: "1.0.0" });
  }
  if (request.method !== "POST") return error(404, "not_found", "找不到這個 API。");
  if (!validToken(request, env.APP_API_TOKEN)) return error(401, "unauthorized", "App Token 無效。");

  const editing = url.pathname === "/v1/images/edits";
  if (!editing && url.pathname !== "/v1/images/generations") {
    return error(404, "not_found", "找不到這個 API。");
  }
  const declaredLength = Number(request.headers.get("content-length") ?? 0);
  if (declaredLength > MAX_BODY_BYTES) return error(413, "payload_too_large", "請求內容過大。");
  if (!request.headers.get("content-type")?.startsWith("application/json")) {
    return error(415, "unsupported_media_type", "請使用 application/json。");
  }

  const rateKey = request.headers.get("cf-connecting-ip") || "shared-app";
  const rate = await env.IMAGE_RATE_LIMITER.limit({ key: rateKey });
  if (!rate.success) return error(429, "rate_limit", "請求過於頻繁，請稍後再試。");

  let payload: ImageRequest;
  try {
    if (!request.body) return error(400, "invalid_json", "請求內容不可空白。");
    const reader = request.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_BODY_BYTES) {
        await reader.cancel();
        return error(413, "payload_too_large", "請求內容過大。");
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const decoded: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
      return error(400, "invalid_json", "請求內容必須是 JSON object。");
    }
    payload = decoded as ImageRequest;
  } catch {
    return error(400, "invalid_json", "請求內容不是有效的 JSON。");
  }

  try {
    const image = await runModel(env, payload, editing);
    return json({ data: [{ b64_json: image }] });
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : "圖片模型執行失敗。";
    if (cause instanceof ApiError) return error(cause.status, cause.code, cause.message);
    const status = typeof cause === "object" && cause !== null && "status" in cause ? Number(cause.status) : 0;
    if (status === 429 || /quota|rate.?limit|daily.*limit|neuron.*limit|10048/i.test(message)) {
      return error(429, "quota_exceeded", "Cloudflare 請求或使用額度已達限制，請稍後重試或手動切換 Provider。");
    }
    console.error("Workers AI request failed", { name: cause instanceof Error ? cause.name : "unknown" });
    return error(502, "model_error", "Cloudflare 圖片模型暫時無法完成請求。");
  }
}

export default { fetch: handleRequest } satisfies ExportedHandler<Env>;
