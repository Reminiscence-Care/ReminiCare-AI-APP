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

## App 執行紀錄（Log）

全 App 右上角固定有 **Log** 按鈕，首頁、回憶流程、歷史／詳細頁、語音快取，以及設定／確認彈窗都可開啟。查看紀錄不離開原流程、不停止正在執行的工作；按返回會回到原頁面或彈窗。Log 頁正在顯示時不重複開啟第二個紀錄頁。

紀錄包含裝置本地時間、App 啟動後經過秒數、流程階段、錄音停止原因、STT 工作／分段進度、語音語言／快取／播放結果、LLM／圖片 HTTP 回應狀態與耗時，以及保存結果。最新在上方，可選取文字、複製全部或清除。只保留本次執行最近 500 筆於記憶體，重啟後清空；一般版亦可查看，debug 版同時印到 `flutter run` 終端。

只接受固定事件／錯誤種類及數字統計，不記 API Key、Token、逐字稿、稱呼、prompt、完整回應或本機檔案路徑。App Log 顯示 App 自身的安全診斷；Flutter 工具的建置／hot reload 訊息與原生引擎輸出仍需查看終端。

進入「請大家介紹自己」時，提示會依序播放台語與中文，沿用可取消的雙語播放協調器；開始錄音或離開流程仍會停止播報。

## 固定測試流程與 CLI 音檔驗收

Debug build 的設定對話框提供「固定測試流程」，預設關閉；儲存後於下一次進入回憶流程生效。Release／profile 隱藏開關並強制停用。啟用後畫面顯示標示，四題固定為「老街、柑仔店、菜市場、老火車」，圖片與問題沿用本地圖庫；重新整理不換題，也不呼叫 LLM 改寫主問題或延伸問題。老街主問題固定為「以前住的街上有哪些店？」，延伸問題固定為「有沒有最熟悉的鄰居？」。手動操作仍使用麥克風，其餘服務照原設定執行。

Windows CLI 入口會直接注入固定模式，不必先操作設定開關，也不改寫其偏好。提供音檔並授權真實服務驗收後，可執行：

```powershell
.\scripts\test-debug-audio.ps1 -Manifest .\testAudio\scenario.json -LiveServices
```

清單格式如下，檔名是示例；相對路徑以清單所在目錄解析，亦支援絕對路徑：

```json
{
  "introduction": ["intro-1.wav", "intro-2.wav"],
  "answer": ["street-answer.wav"],
  "extension": ["street-extension.wav"],
  "revision": ["street-revision.wav"]
}
```

`introduction` 至少一份，`answer`／`extension` 各一份；不測修圖時 `revision` 可省略或填 `[]`。音檔需為 16kHz、單聲道、16-bit PCM WAV；不自動轉檔。啟動後先檢查所有樣本格式，再沿正式 UI 按鈕選老街、確認各位稱呼、分享、依序修圖、延伸分享及保存。測試固定 1366×1024 邏輯布局，無需新增匯入按鈕。每次開始說話以音檔暫存副本代替麥克風；辨識失敗可在 App 重試相同副本，CLI 不自動重跑失敗步驟。原始樣本不被刪除或納入 assets。

此入口只用目前設定的真實 STT／TTS／LLM／生圖服務，會傳資料並可能消耗額度；請先在 App 設定好 Provider 與憑證。`-LiveServices` 是明確啟用參數，一般 `flutter test` 不會執行它。未提供 live 定義的 integration test 也會跳過，不呼叫服務。CLI 的聲音辨識、摘要與圖片不保證每次一致；固定的是問題與操作順序。

每次輸出在被忽略的 `.codex-diagnostics/live-debug/<run-id>/`，圖片與回憶使用隔離 repository，不讀入或清除正式舊版歷史。`acceptance-report.json` 只含階段、耗時、音檔大小／長度、錯誤種類與 CLI 退出碼；流程完成後，腳本仍會檢查測試收尾是否成功。`private-observations.json` 記錄辨識文字與稱呼，與保存的回憶一樣屬於本機私有驗收資料，不輸出或提交。`testAudio/` 與清單亦不提交。首版 CLI 只驗證 Windows；iPad 仍用 debug 開關與實機錄音驗收，音檔注入不能證明麥克風／停頓偵測或硬體穩定性。

## 本批交付與驗收狀態

本批包含固定問答 debug mode、Windows CLI 真實音檔入口、全介面 Log 與雙語自介提示。已完成 Flutter analyze、98 項離線測試及 Windows debug build；較早的四份音檔真實完整流程已通過，證據見 [固定流程真實驗收](docs/debug-audio-validation-2026-10-08.md)。雙語自介本次僅以 fake 驗證順序／取消，尚未做真實聽感或 iPad 硬體驗收。

一般 STT 誤字不直接判定流程失敗，重點是關鍵內容、明顯漏句／重複、人工稱呼確認與可恢復流程。已知保存時可能出現重複圖片副本，引用仍有效，後續修正另行處理。最新提交／推送與待辦請以 Git 和 [工作交接](docs/AI_HANDOFF.md) 核對。

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
