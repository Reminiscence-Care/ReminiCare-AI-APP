# ReminiCare AI

ReminiCare 是以 iPad 橫向為主要裝置的多人回憶治療輔助 App。流程會先推薦四個台灣懷舊主題，再引導長輩自我介紹、以台語／中文聆聽問題、共同分享回憶、產生懷舊圖片並確認或修改，最後保存摘要。

## 架構

- `lib/services/ai/`：OpenAI-compatible 通用文字傳輸、Provider 設定、typed error 與回憶治療領域服務。
- `lib/services/image_gen_api_service.dart`：通用生圖 client、Provider capability、懷舊 prompt 與本地圖片保存。
- `cloudflare/reminicare-image-worker/`：Cloudflare Workers AI 安全代理；Flutter 不持有 Cloudflare 帳號 Token。
- `lib/services/topic_image_search_service.dart`：依受控主題分類向 Wikimedia Commons 取得公開授權照片，包含授權過濾、去重、下載驗證與 100 MB 本機快取。
- `lib/services/remini_care_config.dart`：非敏感偏好與安全金鑰儲存。舊 SharedPreferences 明文 key 會只遷移一次。
- `lib/screens/life_screen/controllers/`：具名事件與 session token 管理；Widget 不直接寫流程狀態。
- `lib/screens/life_screen/widgets/stage_views.dart`：新版 Figma 流程的響應式階段元件。

## AI Provider 設定

設定頁提供 NVIDIA、OpenAI、Gemini、Cloudflare Workers AI、SiliconFlow preset，以及 Custom OpenAI-compatible 文字／生圖端點。新安裝預設以 Cloudflare FLUX.2 Klein 4B 產生及修改正式回憶圖片；既有安裝保留先前選擇，SiliconFlow 仍可手動切換。Cloudflare Worker URL 可修改，App Token 存在安全儲存，不得填入 Cloudflare 帳號 API Token。部署方式見 [`cloudflare/reminicare-image-worker/README.md`](cloudflare/reminicare-image-worker/README.md)。

內建 LLM preset 的模型名稱也可直接修改並保存，例如 NVIDIA 模型更新時不需要重新編譯 App。Custom 必須使用 HTTPS 並提供 Base URL、模型名稱與 API Key。自訂生圖預設只有生成能力；只有宣告 `imageEditing` capability 的 adapter 會使用原圖改圖。

API Key 與語音 Token 透過 `flutter_secure_storage` 保存（iOS Keychain、Android encrypted storage）。Provider、模型、Base URL、錄音秒數與喚醒詞保存在 SharedPreferences。`.env` 僅會在 debug native build 補入記憶體，不會寫回安全儲存；release 不讀 `.env`。

Web build 不會直接呼叫第三方 AI API，也不會把金鑰送往公開 CORS proxy。若要支援 Web，請部署自己的安全後端代理。

Cloudflare 正式圖片輸出為 1024×640，對應新版 Figma 約 1.6:1 的圖片框。改圖前 App 會把參考圖等比例縮至 504 px 以符合模型輸入限制；舊比例圖片以完整前景和模糊背景呈現，不做破壞性裁切。Cloudflare 失敗或達到額度時不會自動切換 SiliconFlow，以免無意消耗另一個 Provider 的額度。

四主題選單不使用生圖或 Vision 額度。LLM 在同一次主題回應內選定受控的懷舊分類；App 對每題只呼叫一次 Wikimedia Commons 分類 API，再下載一張已標示公開授權的照片。四題最多兩題並行，且相同分類與來源圖片不會重複。找不到時顯示本機 placeholder，不會改呼叫生圖 API。卡片右上角可查看作者、來源、授權、原圖與授權頁。正式聊天完成後的回憶圖片仍使用設定的生圖 Provider。

## 執行與測試

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --no-codesign
```

iOS build 需要 macOS 與 Xcode。安裝至 iPad 前，請在 Xcode 設定 Signing Team，並在實機確認麥克風權限、台語／中文 TTS、STT、播放與錄音互斥、生圖時間及完整保存流程。

## 隱私

錄音會交給目前選定的 STT Provider；文字內容及 prompt 會交給所選 LLM／生圖 Provider。Wikimedia Commons 只會收到受控分類名稱，不會收到長輩姓名、錄音、逐字稿或回憶內容。下載的主題縮圖暫存在裝置 cache，產生的回憶圖片與摘要保存在裝置本機。請依實際部署的 Provider 條款，在給長輩使用前取得適當同意，並在重用圖片前確認個別來源頁的授權條件。
