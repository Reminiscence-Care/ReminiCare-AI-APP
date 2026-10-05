# ReminiCare Image Worker

This Worker keeps Cloudflare account credentials out of the Flutter app and exposes only the two image operations ReminiCare needs. It uses the Workers AI binding with `@cf/black-forest-labs/flux-2-klein-4b`.

## Deploy

```powershell
pnpm install --frozen-lockfile
npx wrangler login
npx wrangler secret put APP_API_TOKEN
pnpm test
pnpm run check
pnpm run deploy
```

Generate `APP_API_TOKEN` as a long random value. Do not use a Cloudflare dashboard API token for this secret and do not commit the value. After deployment, enter the resulting `https://...workers.dev` URL and the same App Token in the ReminiCare settings screen.

The deployed endpoint is `https://reminicare-image-api.hding49.workers.dev`.

On Windows, `./scripts/configure-token.ps1` generates the App Token, encrypts a local copy with Windows user protection (`.app-token.xml`, excluded from Git), and uploads the Worker Secret. Run `./scripts/configure-token.ps1 -CopyToClipboard` to copy the token into the Flutter settings. Keep the encrypted file for this account's future tests; it cannot be decrypted by a different Windows user.

`./scripts/smoke-test.ps1` generates four Taiwan memory scenes and performs two successive edits. It saves images in the ignored `smoke-output/` directory and prints elapsed time without exposing the token. These operations consume real Workers AI usage.

`pnpm run dev` uses the remote Workers AI binding and therefore consumes the Cloudflare account's Workers AI allowance.

## App API

- `GET /health`
- `POST /v1/images/generations` with `{ "prompt": "...", "width": 1024, "height": 640 }`
- `POST /v1/images/edits` with the same fields plus `imageBase64` and `imageMimeType`

Image endpoints require `Authorization: Bearer <APP_API_TOKEN>`. Requests are limited to ten image operations per minute per connecting address. Prompts and image bodies are not written to application logs.
