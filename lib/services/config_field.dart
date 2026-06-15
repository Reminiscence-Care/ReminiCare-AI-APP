// =========================================================================
// 💡 設定欄位元數據模型，用於動態生成 UI 與自動儲存
// =========================================================================
class ConfigField {
  final String apiKey;       // 用於 SharedPreferences 與 .env 中的鍵值 (例如: NVIDIA_API_KEY)
  final String displayName;  // 顯示在設定彈窗中的標題 (例如: NVIDIA API KEY)
  final String hintText;     // 文字框內的預留提示字 (例如: nvapi-...)
  final bool isSecure;       // 標記是否為隱私金鑰 (控制小眼睛遮罩顯隱)
  final bool hasDefaultValue; // 標記此欄位是否具有開箱即用的預設值
  final String defaultValue;  // 定義此欄位的預設值內容

  const ConfigField({
    required this.apiKey,
    required this.displayName,
    required this.hintText,
    this.isSecure = true,
    this.hasDefaultValue = false,
    this.defaultValue = "",
  });
}