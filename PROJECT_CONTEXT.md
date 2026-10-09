# ReminiCare 專案脈絡

最後整理：2026-10-09。供 Claude、Codex 與其他協作者的新 session 快速理解；工作規則見 `AGENTS.md`，動態進度見 `docs/AI_HANDOFF.md`，操作見 README。使用通用檔名，不另維護各 AI 的專案脈絡副本。

## 產品與使用方式

ReminiCare 是多人共同使用的回憶治療輔助 App，不是診斷工具。主要流程：

主題選擇 → 多位長輩自我介紹／確認稱呼 → 播報問題 → 分享與錄音 → STT → 場景分析與生圖 → 像／不像 → 延伸分享或修圖 → 摘要與保存。

主要驗收裝置是 iPad 橫向；目前本機開發亦使用 Windows Flutter。播報支援中文／台語；錄音以停頓自動停止搭配手動備援。AI 必須使用雲端 API，不依賴本地模型。

新版 UI 來源為使用者指定的 Figma 2026/10/2 版本：
https://www.figma.com/design/xdo6JkgtKqZG6D8ssO7UOU/Renee-Ong-s-team-library--Copy-?node-id=0-1

這是歷史設計來源，不表示目前 session 已有 Figma 授權或已讀取最新節點；要改設計時重新確認實際存取能力。

## 導覽：從問題找程式

| 範圍 | 入口與責任 |
| --- | --- |
| 流程／重試／session | `lib/screens/life_screen/controllers/life_screen_controller.dart` |
| 生命周期／UI | `lib/screens/life_screen/life_screen.dart`、`widgets/stage_views.dart` |
| 稱呼確認 | `lib/models/participant_address.dart`、`widgets/participant_address_dialog.dart`（widgets 位於 life_screen 下） |
| 錄音／播放協調 | `lib/services/audio_services/voice_assistant_services.dart` |
| 可注入硬體 ports／播放結果 | `lib/services/audio_services/audio_ports.dart` |
| 錄音狀態／音量／停止 | `lib/services/audio_services/recording_controller.dart`、`speech_pause_detector.dart` |
| WAV／成大分段 | `lib/services/audio_services/wav_audio.dart`、`ncku_segmented_stt.dart` |
| STT job／錯誤 | `lib/services/audio_services/speech_recognition_job.dart`、`stt_result.dart` |
| 成大 TTS／雅婷 adapters | `lib/services/audio_services/speech_services.dart` |
| TTS 快取 | `lib/services/audio_services/tts_cache.dart` |
| LLM 傳輸／領域操作 | `lib/services/ai/llm_client.dart`、`reminiscence_ai_service.dart` |
| JSON／取消／Provider | `lib/services/ai/provider_response_parser.dart`、`ai_http_transport.dart`、`provider_registry.dart` |
| 圖片生成／改圖／本地保存 | `lib/services/image_gen_api_service.dart` |
| 固定主題與圖片 | `lib/services/topic_catalog.dart`、`assets/topics/catalog.json` |
| 設定／安全儲存 | `lib/services/remini_care_config.dart` |
| 回憶資料／歷史 | `lib/models/conversation_turn.dart`、`lib/services/memory_repository.dart`、`lib/screens/history_screen.dart` |
| 雲端生圖後端 | `cloudflare/reminicare-image-worker/`（TypeScript，與 Flutter 同 repo） |
| CI | `.github/workflows/check.yml`；既有 IPA 工作流程為 `build-ipa.yml` |

## 已定案的架構與行為

### 主題與稱呼

- 本地 12 組授權圖片／主題，每輪抽四個、優先避開上一輪。標題與圖片不能被 LLM 改寫。
- LLM 一次為選定 topicId 產生問題；失敗或提早選題使用預設問題。開始的對話不被遲到問題覆蓋。
- 曾嘗試 Openverse＋雲端 Vision 選圖，但相關度和速度不理想，已移除；不要把它當待完成方案恢復。
- 姓氏辨識有同音字限制，因此保留人工確認／常用姓氏／手動輸入；未指定稱謂使用「長輩」。

### App 內執行紀錄

- `AppLog` 是共用的有界記憶體紀錄器（最近 500 筆），只接受固定事件／領域、白名單 detail 與數字指標，debug 終端同步輸出；不攔截任意 print 或保存私人內容。
- `MaterialApp.builder` 的 `AppLogOverlay` 包住 root Navigator，按鈕跨頁面與 dialog 可用；現有 AppBar 保留右側空間。查看 Log 使用獨立路由，返回保留原頁面與流程。
- `AppLogScreen` 即時顯示本地時間、相對時間、事件／進度／耗時，支援複製與清除；只在查看時維持更新計時器。
- 接入 recording state／stop、STT job／分段 HTTP、TTS cache／播放、AI HTTP、Controller 階段／錯誤／保存與設定。任意 Provider 錯誤訊息改為固定錯誤種類，避免內容或憑證進入紀錄。
- 自我介紹入口和問題階段一致使用台語→中文的取消式播放序列；不變更音訊互斥或取消協調。

### 固定測試流程（debug-only）

- 設定偏好 `DEBUG_FIXED_FLOW` 預設 false；Controller 初始化時鎖定，CLI 可用建構參數覆寫而不寫回偏好。所有來源皆受 `kDebugMode` 限制，release／profile 不啟用。
- 固定題組 street／grocery／market／railway，沿用 catalog 的問題與圖片，跳過主題問題生成與動態追問；其他真實服務照原設定執行。
- `DebugAudioSource` 只在固定模式注入時生效，按既有錄音按鈕消耗 introduction／answer／extension／revision 樣本；副本進既有 STT job 與重試，原檔不交給刪除流程。
- Windows integration test 從 CLI 清單注入音檔，以正式 Widget keys 走多人自介、分享、修圖、延伸及保存。固定 1366×1024 邏輯布局；不增加音檔匯入 UI，不處理 Windows resize。
- `LocalImageStore.directory` 與 `MemoryRepository(directory, migrateLegacy: false)` 支援隔離驗收資料，不污染正式圖片／回憶或移除舊歷史偏好。啟動操作與清單格式見 README；live 測試仍需當次授權。

### 音訊與辨識

- PCM16、16kHz、mono WAV；解析 fmt/data chunks，不假設固定 44-byte header。
- 自介停頓預設 3 秒，聊天／修圖 6 秒；皆可設 1–30 秒、一位小數。未開口等待 15 秒；最長錄音預設 180 秒、範圍 15–600 秒。
- 單一協調器管理麥克風與播放器；ports 可注入 fake。iOS recorder 自管 session 關閉，交由協調器處理。
- 校正最多一秒，立即說話仍偵測；三次音量讀取失敗轉手動提示，最長錄音獨立限制仍有效。
- 播放區分完成／取消／失敗，停止會解除等待；啟動／停止期限 10／5 秒，播放上限 2 分鐘。
- 每次 STT 有自己的 job、progress、取消；不讓共用 callback 覆蓋其他工作。成大最多兩段並行，順序合併，保留成功段落供失敗重試。
- 成大分段至多 5 秒、編碼請求保守低於 240 KiB；413（含包在 500 裡）縮段。此數字不是實驗室確認的限制。
- 雅婷 connect/ready 10/5 秒，送完音訊後等待 EOF 最多 30 秒；未 EOF 的文字是部分結果，不是成功。仍按接近即時速度傳音訊，長錄音有傳送等待。
- 辨識成功清理原錄音；失敗留當次 session，重錄／離開／過期清理。背景／中斷保留可用音檔供明確辨識或重錄。

### AI 與保存

- 文字使用通用 OpenAI-compatible client＋回憶領域 service；preset 模型可在設定修改，不能假定雲端模型名稱永久可用。
- 通用生圖 client＋Provider adapter；能力判斷區分真正原圖編輯與重新生成。
- Cloudflare Worker 名稱 `reminicare-image-api`，使用 Workers AI binding；部署／Token／會消耗額度的測試見 Worker README。本輪穩定性更新沒有重新部署 Worker。
- Abortable HTTP 與 session checks 防舊回應；已受理的雲端計算／計費不能保證取消。
- `ConversationTurn` 分 memory/correction；累積分享進 prompt，修圖不覆蓋原回憶；年代與地點傳入 prompt builder。
- `MemoryRepository` 使用 schemaVersion 2、穩定 ID、逐筆 JSON、原子發布與相對圖片路徑。
- 裝置 Documents 下 `reminicare_memories/` 保存紀錄，`reminicare_images/` 管理圖片；舊 `chat_memories` 先備份至 `legacy-backup.json` 再遷移。清理需檢查所有引用。
- 設定以快照提交，安全儲存失敗有補償回復；秘密放 secure storage，非敏感值放 SharedPreferences。`.env` 僅 debug 補入記憶體。
- TTS cache key 包含 Provider／端點／聲音／語言／文字，避免切換服務還播舊音。

## 驗收判準與本批交付

固定模式、CLI 音檔、全介面 Log 與雙語自介已實作；本批提交同時包含規則、操作與交接文件。自動驗證為 analyze／98 tests／Windows debug build；先前真實 Windows 音檔流程通過，雙語自介聽感與 iPad 硬體仍未驗收。

使用者接受 STT 一般誤字，字元相似度只作參考，不是 pass/fail 門檻。驗收看固定問題、關鍵內容、明顯漏句／重複、人工稱呼確認、可恢復處理與保存。真實驗收發現 3 種圖片內容留下 9 個檔案，引用有效；Windows 路徑比較／多處引用複製是待診斷方向，尚未修正。

## 已知限制與不在範圍內的事

- 成大是外部實驗室服務，使用者無權改服務端；目前 HTTP STT／raw TCP TTS 未加密。保留此風險說明，不要求使用者改伺服器，不將 TLS 當本輪阻塞。現有端點設定只供可用端點變動，不表示 TLS 已部署。
- 長錄音實測是 App 端品質驗收，不需要成大配合；短錄音成功不代表長錄音接合品質或硬體穩定性已證明。
- Windows 放大／縮小曾黑白畫面或點擊異常，使用者因主要部署 iPad 而暫停此項修復；不要無關修改 plugin registry。
- iPad 實機錄音、音訊中斷、背景切換尚待驗收；未簽章 iOS build 成功不等於可直接安裝。
- Web 不直接帶 key 呼叫第三方 AI；沒有自有安全代理不支援。不使用公開 CORS proxy。
- 不恢復音樂／YouTube／Spotify、不使用短效 Figma URL 作資產；圖片授權資訊不可刪。

## 維護原則

不要把本檔當永久最新測試報告。更新架構或既定決策時同步修改；下一步／卡點／測試結果寫 `docs/AI_HANDOFF.md`，歷史證據留驗收文件。新 session 要以實際程式與 Git 狀態覆核。
