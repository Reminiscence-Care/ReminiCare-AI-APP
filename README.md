# ReminiCare AI

ReminiCare 是以 iPad 橫向為主要裝置的多人回憶治療輔助 App。流程會先推薦四個台灣懷舊主題，再引導長輩自我介紹、以台語／中文聆聽問題、共同分享回憶、產生懷舊圖片並確認或修改，最後保存摘要。

## Claude／Codex 新 session 與工作交接

請依序閱讀 [AGENTS.md](AGENTS.md) 的共同規則、本文、[專案脈絡](PROJECT_CONTEXT.md) 與 [目前工作交接](docs/AI_HANDOFF.md)，並核對實際 Git 分支、未提交改動與近期提交。Claude 另有 [CLAUDE.md](CLAUDE.md) 作入口；所有協作者共用同一份脈絡與交接，不重複維護現況。

可在新 session 貼上：「請先讀 AGENTS.md、README.md、PROJECT_CONTEXT.md、docs/AI_HANDOFF.md，確認目前分支與工作狀態，摘要已完成及待驗收項目；先不要更改程式，等我指定本次任務。」本機 `.env`、真實錄音與 Token 不放入交接文件。工作告一段落時更新交接，架構／操作變更則同步更新脈絡與 README。

## 架構

- `lib/services/ai/`：OpenAI-compatible 通用文字傳輸、Provider 設定、typed error 與回憶治療領域服務。
- `lib/services/image_gen_api_service.dart`：通用生圖 client、Provider capability、懷舊 prompt 與本地圖片保存。
- `cloudflare/reminicare-image-worker/`：Cloudflare Workers AI 安全代理；Flutter 不持有 Cloudflare 帳號 Token。
- `lib/services/topic_catalog.dart`：離線圖片與固定主題圖庫；即時圖片搜尋及 Vision 排序已移除。
- `lib/services/audio_services/`：錄音／播放 port、音訊協調器、停頓偵測、可取消 STT job 及 Provider／聲音分開的 TTS 快取。
- `lib/services/memory_repository.dart`：逐筆 JSON 回憶、舊紀錄備份遷移、相對圖片路徑與引用清理。
- `lib/services/remini_care_config.dart`：非敏感偏好與安全金鑰儲存。舊 SharedPreferences 明文 key 會只遷移一次。
- `lib/screens/life_screen/controllers/`：具名事件與 session token 管理；Widget 不直接寫流程狀態。
- `lib/screens/life_screen/widgets/stage_views.dart`：新版 Figma 流程的響應式階段元件。

## AI Provider 設定

設定頁提供 NVIDIA、OpenAI、Gemini、Cloudflare Workers AI、SiliconFlow preset，以及 Custom OpenAI-compatible 文字／生圖端點。新安裝預設以 Cloudflare FLUX.2 Klein 4B 產生及修改正式回憶圖片；既有安裝保留先前選擇，SiliconFlow 仍可手動切換。Cloudflare Worker URL 可修改，App Token 存在安全儲存，不得填入 Cloudflare 帳號 API Token。部署方式見 [`cloudflare/reminicare-image-worker/README.md`](cloudflare/reminicare-image-worker/README.md)。

內建 LLM preset 的模型名稱也可直接修改並保存，例如 NVIDIA 模型更新時不需要重新編譯 App。Custom 必須使用 HTTPS 並提供 Base URL、模型名稱與 API Key。自訂生圖預設只有生成能力；只有宣告 `imageEditing` capability 的 adapter 會使用原圖改圖。

API Key 與語音 Token 透過 `flutter_secure_storage` 保存（iOS Keychain、Android encrypted storage）。Provider、模型、Base URL、錄音秒數與喚醒詞保存在 SharedPreferences。`.env` 僅會在 debug native build 補入記憶體，不會寫回安全儲存；release 不讀 `.env`。

Web build 不會直接呼叫第三方 AI API，也不會把金鑰送往公開 CORS proxy。若要支援 Web，請部署自己的安全後端代理。

Cloudflare 正式圖片輸出為 1024×640，對應新版 Figma 約 1.6:1 的圖片框。改圖前 App 會把參考圖等比例縮至 504 px 以符合模型輸入限制；舊比例圖片以完整前景和模糊背景呈現，不做破壞性裁切。Cloudflare 失敗或達到額度時不會自動切換 SiliconFlow，以免無意消耗另一個 Provider 的額度。

四主題選單使用 `assets/topics/catalog.json` 的十二組固定圖片與主題，本地抽四題並優先避開上一輪，無須網路即可顯示。LLM 一次替這四個 topicId 產生問題；回應尚未完成就選題時使用預設問題，後續回應不替換已開始的對話。LLM 不修改圖片或主題標題。資訊按鈕提供作者、授權及示意照片標示。正式聊天完成後的回憶圖片仍使用設定的生圖 Provider。

## 錄音與辨識

自我介紹只顯示「姓氏＋稱謂」。同音字無法只靠語音保證正確，請確認畫面上的稱呼；可按「修改稱呼」選同音候選、展開常用姓氏表，或手動輸入罕見姓氏並調整稱謂。候選不會自動替換辨識結果，修改不增加雲端 API 呼叫。確認正確後按「下一位」或「開始聊天」才加入參與者資料；辨識失敗也可手動填寫。未指定稱謂預設使用「長輩」。

設定頁可分別調整自我介紹（預設 3 秒）、聊天／修圖（預設 6 秒）的說完後等待時間，接受 1–30 秒與一位小數。這和最長錄音秒數分開；開始說話前最多等待 15 秒。錄音使用 16kHz、單聲道、16-bit WAV。

最長錄音可設定 15–600 秒，預設 180 秒。環境校正最多一秒，開頭說話也會參與停頓偵測；音量取樣连续失敗時提示改用「說完了」，最長限制仍生效。App 進入背景或音訊／輸入裝置中斷時保留可用錄音，回到流程可選擇辨識或重新錄音。播放停止、逾時與失敗都會結束等待。

雅婷必須收到 `asr_eof` 才判定完整成功，完成期限預設為音訊送完後 30 秒。部分結果不會觸發姓名確認或生圖。雅婷目前仍以服務要求的接近即時速度送出已錄音訊，長錄音等待時間包含音訊傳送時間；未改成未知支援度的高速傳送。

STT 成功而生圖失敗時，可按「重試處理」，不用重新錄音。回憶以多輪資料保存，修圖指令與原分享分開；產圖使用累積內容及 LLM 擷取的年代、地點。回憶保存使用穩定 ID 避免連點重複，舊資料備份位於裝置文件目錄 `reminicare_memories/legacy-backup.json`，損壞單筆不阻止其他紀錄載入。

成大 STT／TTS 是外部實驗室管理的服務，使用者無法修改服務端。端點可設定，TTS client 支援 TLS，但現有預設 HTTP／未加密 TCP 仍是已知限制，不能靠 App 單方面解決；本輪不要求實驗室修改，也不把它當成錄音驗收的前提。若日後部署要求加密，再另行評估可用端點或 Provider。App 不會把一般 TCP 標記為已加密。

成大 STT 將長錄音分成至多 5 秒的完整音訊段落，每個編碼後請求保守限制在 240 KiB；遇到 413 再縮段，最多兩段並行並按原順序合併。失敗時保留本次錄音並顯示重試，成功段落不重送。辨識成功、重新錄音或離開流程後清除錄音；過期暫存檔會在啟動時清理。真實中文／台語及 iPad 驗收狀態見 `docs/recording-topic-validation.md`。

## 執行與測試

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --no-codesign
```

iOS build 需要 macOS 與 Xcode。安裝至 iPad 前，請在 Xcode 設定 Signing Team，並在實機確認麥克風權限、台語／中文 TTS、STT、播放與錄音互斥、生圖時間及完整保存流程。

一般 push／PR 的 CI 執行 Flutter analyze／test、Android debug、macOS 未簽章 iOS debug build，以及 Worker 型別／單元測試。2026-10-08 的驗證與實機待驗收項目見 [穩定性驗收紀錄](docs/stability-validation-2026-10-08.md)。本機真實語音測試資料放在被 Git 忽略的 `testAudio/`。

## 隱私

錄音會交給目前選定的 STT Provider；文字內容及 prompt 會交給所選 LLM／生圖 Provider。主題圖片已隨 App 打包，執行時不向 Wikimedia Commons 搜尋或上傳資料。產生的回憶圖片與摘要保存在裝置本機。請依實際部署的 Provider 條款，在給長輩使用前取得適當同意，並在重用圖片前確認個別來源頁的授權條件。
