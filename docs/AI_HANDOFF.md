# AI 工作交接

最後更新：2026-10-09。這是目前進度摘要，不是自動啟動工作的授權；接手後以使用者最新要求及實際 Git 狀態為準。

## 最新：文件同步與提交交付

2026-10-09 使用者明確授權將本批改動更新至 AGENTS／README／PROJECT_CONTEXT／本檔，再提交並推送。此文件所在的功能提交包含固定模式、CLI 真實音檔、全介面 Log、雙語自介、回歸測試與驗收紀錄；提交／推送是否完成以實際 Git HEAD、remote 與本輪回覆核對，不以歷史段落的「未提交」認定現況。

- 分支 `codex/figma-ui-2026-10-02`，交付前基準 `efe6c25`；不修改 `no-music-screen`。
- 最新功能驗證證據：analyze 無問題、98 tests 通過、Windows debug build 成功。本次文件同步僅重新做 diff／本地連結／提交內容檢查，未冒用舊結果為新測試。
- 音檔、audioDetails、測試清單、私有 observations、憑證與 `.codex-diagnostics/` 不納入提交；不部署 Worker。
- 使用者已釐清 STT 一般差異是可接受限制，不是本次流程驗收失敗。待辦維持重複圖片副本診斷、真實雙語聽感、iPad 音訊及其他長中文／台語驗收；未順帶實作。

## 前輪：全介面 Log 與雙語自介

2026-10-09 使用者要求每個介面均可查看執行紀錄，並指出自介只播台語。已加入全域右上角 Log，與台語→中文自介序列；保留原本未提交的固定模式／真實驗收改動。分支仍為 `codex/figma-ui-2026-10-02`，HEAD `efe6c25`。

- 全域 Log 跨首頁、流程、歷史／詳細、快取、彈窗及 CLI App 可用，返回保留原畫面。最近 500 筆、即時更新、複製／清除，重啟清空；debug 終端同步印出。
- 事件涵蓋時間、錄音、STT／TTS、LLM／圖片請求、流程與保存。只記固定類別及數字，不捕捉任意終端輸出，不保存逐字稿／稱呼／秘密／回應本文。
- 自介改為雙語播放，既有互斥／取消機制保留。新增測試確認入口的語言順序、實際 fake 播放順序與取消後不啟動第二語言。
- 已自動驗證：`flutter analyze` 無問題；`flutter test --reporter expanded` 98 tests 通過；`flutter build windows --debug` 成功；diff 檢查通過。
- 新增 5 項回歸（2 Log／1 自介設定／2 播放序列），含每個路由與 dialog 開啟、即時更新、清除／返回、有界與隱私限制。
- 未做真實 TTS 聽感、iPad 硬體或 release／profile build 驗收；本輪無雲端呼叫、部署、commit 或 push。保存重複圖片問題維持待辦，沒有順帶修改。

## 前輪：使用者音檔真實驗收

2026-10-08 使用者提供四份老街 WAV 與標註並授權測試，最後一輪 Windows 真實 integration test + CLI 通過（退出碼 0）。完成自介、分享、生圖、修圖、固定延伸與隔離保存；四份原檔雜湊相同。

- 共三輪：修正測試畫面幀同步及 Windows `SemanticsHandle` 收尾問題後，第三輪通過。只有測試入口與文件變更，未修正式保存／服務流程。
- 保存 1 筆、3 輪（2 memory／1 correction）、3 圖片版本；原分享與修圖分開。所有圖片引用存在。
- 字元序列相似度：分享 82.1%、延伸 88.7%、修圖 92.3%，不當作正式辨識準確率；仍需文字品質驗收。
- 發現隔離保存有 9 圖片檔案但僅 3 種內容，重複副本問題待授權診斷／修正；目前沒有引用遺失。
- 本輪 analyze、固定流程 13 tests、PowerShell 語法與 diff 檢查通過。未重跑全部 93 tests 或其他平台 build。未做 iPad 硬體驗收、commit、push 或部署。
- 詳細結果：[debug-audio-validation-2026-10-08.md](debug-audio-validation-2026-10-08.md)。本機 run `32e38455-7a59-4cd9-811e-6181ad1c7408` 的匿名報告與私有證據留在被忽略的 `.codex-diagnostics/live-debug/`。

## 固定模式實作交接（真實驗收前）

本輪已依使用者核准計畫實作固定問答 debug mode 與 CLI 真實音檔驗收入口。工作分支仍為 `codex/figma-ui-2026-10-02`，開始時工作目錄乾淨，HEAD `efe6c25`。本輪變更尚未提交／推送；未部署 Worker，未執行真實雲端服務或讀取使用者語音樣本。

- Debug 設定開關可保存／取消，下一次流程才生效；CLI 建構參數優先、不改偏好。Release／profile 以 `kDebugMode` 強制停用。
- 固定老街、柑仔店、菜市場、老火車及 catalog 原問題，刷新不換題；固定延伸追問跳過 LLM，姓名／分析／摘要／圖片仍走既有流程。
- `scripts/test-debug-audio.ps1` + integration test 以本機清單注入音檔，直接啟用固定模式，操作正式 Widget keys，支援多人自介與選配修圖。所有樣本先驗證；辨識只處理可清理副本，保留原檔。
- 真實測試圖片、回憶與匿名報告存於 `.codex-diagnostics/live-debug/`，隔離 repository 不遷移或清除正式歷史。CLI 需明確 `-LiveServices`；日常測試不呼叫雲端。
- 設定 Widget 回歸發現對話框關閉後過早釋放輸入控制器，已改為退出動畫完成才釋放。
- 本輪新增 13 項測試：固定與正常問答、偏好／CLI 覆寫、麥克風保留、樣本清理／重試、連點、離開／dispose／舊 STT、清單錯誤、隔離遷移，以及完整多人 UI 自介／修圖／延伸／保存。

## 固定模式實作時的本機驗證（2026-10-08，HEAD efe6c25 上的未提交改動）

- `flutter test --reporter expanded`：93 tests 通過，包含新增 13 tests；服務使用 fake／合成資料。
- `flutter analyze`：無問題。
- `flutter build windows --debug`：成功；未驗證 release／profile build 或 iOS／Android build。
- Windows integration test 在未提供 live 定義時成功編譯啟動，1 項真實驗收跳過；不等於已通過真實服務驗收。
- PowerShell CLI 腳本通過語法解析；尚未以使用者音檔執行。
- 未做 iPad 實機／麥克風硬體驗收；不推論硬體穩定性。Windows resize 維持暫緩。

先前穩定性提交：`72b36cb`（音訊／STT／AI／保存）、`843406a`（iOS xcconfig）、`a4b60f8`（iOS CI 紀錄）、`efe6c25`（共用交接文件）。舊驗證保留如下，非本輪重新驗證。

## 先前已驗證的證據（非本次重新測試）

- 2026-10-08：Flutter analyze 無問題；Flutter 80 tests 通過；Windows／Android debug build 通過。
- Worker 型別檢查與 13 tests 通過，穩定性改動未部署 Worker。
- GitHub CI [run 37674070644](https://github.com/Reminiscence-Care/ReminiCare-AI-APP/actions/runs/37674070644)，程式 revision `843406a`：Flutter 分析／測試、Android debug、macOS iOS debug `--no-codesign`、Worker 全部成功。
- 本機一份真實中文樣本約 3.12 秒、99,982-byte WAV、177,715-byte 編碼請求，成大約 490 ms 成功，姓氏與本機標註相符；未公開完整逐字稿或 Token。
- 樣本在被 Git 忽略的 `testAudio/`，不是保證所有 checkout 都存在；不得提交或自行刪除。
- 詳細證據：[stability-validation-2026-10-08.md](stability-validation-2026-10-08.md)。較早紀錄 [recording-topic-validation.md](recording-topic-validation.md) 只作歷史參考，不覆蓋新版結果。

## 待驗收與下一步建議

沒有已知需要繼續修的 CI 失敗，亦沒有預設需要要求成大修改服務端的任務。下一步需使用者授權／提供環境或樣本：

1. Windows 老街固定流程已完成真實音檔驗收。若使用者授權下一輪實作，優先診斷保存時的重複圖片副本，保留現有資料與所有引用。
2. 真實中／長中文與台語：記錄每段與總耗時，核對切段邊界漏字、重複、接合；暫維持 5 秒／240 KiB，不能僅為速度放寬。
3. 實體 iPad：立即開口、輕聲、背景噪音、長停頓、手動／自動同時停止、拒絕權限、背景前景、輸入裝置切換、取消播放、長錄音。
4. 用真實歷史的副本驗證舊資料遷移、失敗重試、共用圖片引用刪除；保留 migration backup。
5. 驗證「STT 成功但 LLM／生圖失敗 → 只重試後段」與完整多人聊天／修改／保存流程。

驗收目標：失敗可見且可恢復、可用錄音不遺失、無流程卡住或舊回應跳頁、錄音與播報不搶占。自動測試不代替硬體驗收。

成大 STT／TTS 未加密是既有外部限制，使用者無法干涉實驗室伺服器。若未來有部署安全需求，另討論方案；不要把它當長錄音測試的前提。

## 接手檢查

```sh
git status --short
git branch --show-current
git log -5 --oneline
flutter --version
```

CI 使用 Flutter 3.41.9；pubspec 要求 Dart ^3.11.5。Worker 使用 Node 22 與 pnpm 11.19.0。依實際環境執行，不把前一個 session 的絕對 SDK 路徑寫進共用設定。

先閱讀 `AGENTS.md`／README／`PROJECT_CONTEXT.md`，再針對新任務讀相關 code/test。基準指令為 `flutter analyze`、`flutter test`；Worker 在其目錄執行 `pnpm check`、`pnpm test`。真實雲端測試與部署需要確認授權與額度。

## 每次交接應更新的欄位

- 日期、使用者當次目標與明確不處理的範圍。
- 分支、完成提交／是否推送、未提交改動與不可覆蓋的使用者檔案。
- 已完成工作、進行中步驟、卡點及下一個可執行動作。
- 實際執行的測試／build、revision、結果；未執行／未實機驗收也寫明。
- 設定／資料遷移／外部服務限制與需使用者決定之處。

只保留足夠接手的摘要；歷史細節移入日期化驗收文件，不貼 Token、完整逐字稿或整段對話。不因先前交接寫了「下一步」就自行部署、花額度或改原分支。
