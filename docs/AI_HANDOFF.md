# AI 工作交接

最後更新：2026-10-08。這是目前進度摘要，不是自動啟動工作的授權；接手後以使用者最新要求及實際 Git 狀態為準。

## 最近工作

已完成使用者要求的三階段穩定性程式改動：音訊生命周期、可取消辨識／累積回憶、歷史保存／設定／維護整理。現在新增跨 Claude／Codex 文件入口，未繼續處理 Windows resize。

- 工作分支：`codex/figma-ui-2026-10-02`，原始基準 `no-music-screen` 不改。
- `72b36cb`：音訊 ports／控制器、可取消 STT 與 AI、累積對話、MemoryRepository、設定回復、移除舊搜尋／Vision、新 CI。
- `843406a`：修復 iOS Runner xcconfig 引用，恢復 Flutter generated settings 繼承。
- `a4b60f8`：記錄 iOS CI 成功；上述三筆已推送。
- 本次文件交付：`AGENTS.md`、`CLAUDE.md`、通用的 `PROJECT_CONTEXT.md`、本檔與 README；同步釐清成大外部服務限制。使用者已要求將此批文件提交並推送；是否完成及提交 ID 以實際 Git／remote 狀態為準。

## 已驗證的證據（非本次重新測試）

- 2026-10-08：Flutter analyze 無問題；Flutter 80 tests 通過；Windows／Android debug build 通過。
- Worker 型別檢查與 13 tests 通過，穩定性改動未部署 Worker。
- GitHub CI [run 37674070644](https://github.com/Reminiscence-Care/ReminiCare-AI-APP/actions/runs/37674070644)，程式 revision `843406a`：Flutter 分析／測試、Android debug、macOS iOS debug `--no-codesign`、Worker 全部成功。
- 本機一份真實中文樣本約 3.12 秒、99,982-byte WAV、177,715-byte 編碼請求，成大約 490 ms 成功，姓氏與本機標註相符；未公開完整逐字稿或 Token。
- 樣本在被 Git 忽略的 `testAudio/`，不是保證所有 checkout 都存在；不得提交或自行刪除。
- 詳細證據：[stability-validation-2026-10-08.md](stability-validation-2026-10-08.md)。較早紀錄 [recording-topic-validation.md](recording-topic-validation.md) 只作歷史參考，不覆蓋新版結果。

## 待驗收與下一步建議

沒有已知需要繼續修的 CI 失敗，亦沒有預設需要要求成大修改服務端的任務。下一步需使用者授權／提供環境或樣本：

1. 真實中／長中文與台語：記錄每段與總耗時，核對切段邊界漏字、重複、接合；暫維持 5 秒／240 KiB，不能僅為速度放寬。
2. 實體 iPad：立即開口、輕聲、背景噪音、長停頓、手動／自動同時停止、拒絕權限、背景前景、輸入裝置切換、取消播放、長錄音。
3. 用真實歷史的副本驗證舊資料遷移、失敗重試、共用圖片引用刪除；保留 migration backup。
4. 驗證「STT 成功但 LLM／生圖失敗 → 只重試後段」與完整多人聊天／修改／保存流程。

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
