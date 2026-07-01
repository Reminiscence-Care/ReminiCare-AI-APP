import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';
import 'package:remini_care_ai_app/services/api_services.dart'; // 💡 引入統一服務中心

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  /// 💡 智慧檢查：只檢查「當前選定」的模型是否有填寫金鑰
  bool _isConfigComplete() {
    // 1. 檢查 LLM
    final llmProvider = ReminiCareConfig.getValue('selectedLlmProvider') ?? 'nvidia';
    bool llmOk = false;
    if (llmProvider == 'nvidia') llmOk = ReminiCareConfig.nvidiaApiKey.isNotEmpty;
    if (llmProvider == 'openai') llmOk = ReminiCareConfig.openaiApiKey.isNotEmpty;
    if (llmProvider == 'gemini') llmOk = ReminiCareConfig.geminiApiKey.isNotEmpty;

    // 2. 檢查 生圖
    final imageProvider = ReminiCareConfig.getValue('selectedImageProvider') ?? 'siliconflow';
    bool imageOk = false;
    if (imageProvider == 'siliconflow') imageOk = ReminiCareConfig.siliconFlowApiKey.isNotEmpty;
    if (imageProvider == 'openai') imageOk = (ReminiCareConfig.getValue('openaiApiKey') ?? "").isNotEmpty;

    // 3. 檢查 語音
    final speechProvider = ReminiCareConfig.getValue('selectedSpeechProvider') ?? 'yating';
    bool speechOk = false;
    if (speechProvider == 'yating') speechOk = ReminiCareConfig.yatingApiKey.isNotEmpty;
    if (speechProvider == 'ncku') {
      speechOk = ReminiCareConfig.nckuSttToken.isNotEmpty && ReminiCareConfig.nckuTtsToken.isNotEmpty;
    }

    return llmOk && imageOk && speechOk;
  }

  @override
  void initState() {
    super.initState();
    ReminiCareConfig.loadConfig();
  }

  // =========================================================================
  // 攔截提醒視窗：引導使用者前往設定
  // =========================================================================
  void _showConfigWarning() {
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Text("需要設定 API 金鑰", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: const Text(
              "您必須先點擊右上角的「齒輪」完成所有的系統配置（填寫 API 金鑰），才能開始使用這些陪伴功能喔！",
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("稍後再說", style: TextStyle(color: Colors.grey, fontSize: 16)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showSettingsDialog();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey[800],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("前往設定", style: TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ],
          );
        }
    );
  }

  // =========================================================================
  // 互動式自訂設定視窗 (支援下拉選單無縫切換 Provider)
  // =========================================================================
  void _showSettingsDialog() {
    final Map<String, TextEditingController> controllers = {};
    for (var field in ReminiCareConfig.fields) {
      controllers[field.apiKey] = TextEditingController(
        text: ReminiCareConfig.getValue(field.apiKey),
      );
    }

    final Map<String, bool> obscureStates = {};
    for (var field in ReminiCareConfig.fields) {
      obscureStates[field.apiKey] = true;
    }

    // 💡 讀取目前的 Provider 設定 (若無則給預設值)
    String selectedLlm = ReminiCareConfig.getValue('selectedLlmProvider') ?? 'nvidia';
    String selectedSpeech = ReminiCareConfig.getValue('selectedSpeechProvider') ?? 'yating';
    String selectedImage = ReminiCareConfig.getValue('selectedImageProvider') ?? 'siliconflow';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: const [
                    Icon(Icons.settings, color: Colors.blueGrey),
                    SizedBox(width: 8),
                    Text("ReminiCare AI 配置", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "在此選擇您想使用的 AI 引擎並填寫對應金鑰。設定完成後立即套用生效！",
                          style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                        ),
                        const SizedBox(height: 16),

                        // ==========================================
                        // 🛠️ Provider 選擇區塊 (下拉選單)
                        // ==========================================
                        _buildDropdown(
                          "大語言模型 (LLM)",
                          selectedLlm,
                          [
                            {"value": "nvidia", "label": "NVIDIA (Qwen 80B)"},
                            {"value": "openai", "label": "OpenAI (GPT-4o-mini)"},
                            {"value": "gemini", "label": "Google Gemini (1.5 Flash)"},
                          ],
                              (val) => setStateDialog(() => selectedLlm = val!),
                        ),
                        _buildDropdown(
                          "語音服務 (STT & TTS)",
                          selectedSpeech,
                          [
                            {"value": "yating", "label": "雅婷 (Yating)"},
                            {"value": "ncku", "label": "成大 (NCKU VITS)"},
                          ],
                              (val) => setStateDialog(() => selectedSpeech = val!),
                        ),
                        _buildDropdown(
                          "生圖服務 (Image Gen)",
                          selectedImage,
                          [
                            {"value": "siliconflow", "label": "SiliconFlow (Qwen)"},
                            {"value": "openai", "label": "OpenAI (DALL-E 3)"},
                          ],
                              (val) => setStateDialog(() => selectedImage = val!),
                        ),

                        const Divider(height: 32, thickness: 1.5),

                        // ==========================================
                        // 🔑 API Keys 填寫區塊 (動態生成)
                        // ==========================================
                        ...ReminiCareConfig.fields.map((field) {
                          final controller = controllers[field.apiKey]!;
                          final isObscured = obscureStates[field.apiKey] ?? true;

                          return _buildSettingsField(
                            field.displayName,
                            controller,
                            field.hintText,
                            isObscured,
                            field.isSecure,
                                () {
                              setStateDialog(() {
                                obscureStates[field.apiKey] = !isObscured;
                              });
                            },
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      for (var controller in controllers.values) {
                        controller.dispose();
                      }
                      Navigator.of(context).pop();
                    },
                    child: const Text("取消", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      // 1. 收集 Controller 中的金鑰
                      final Map<String, String> updatedData = {};
                      controllers.forEach((key, controller) {
                        updatedData[key] = controller.text;
                      });

                      // 2. 💡 收集下拉選單的 Provider 設定
                      updatedData['selectedLlmProvider'] = selectedLlm;
                      updatedData['selectedSpeechProvider'] = selectedSpeech;
                      updatedData['selectedImageProvider'] = selectedImage;

                      // 3. 儲存設定
                      await ReminiCareConfig.saveConfig(updatedData);

                      // 4. 💡 核心：清除 API 快取，讓系統下次使用時實例化新的 Provider！
                      ApiServices().resetCache();

                      for (var controller in controllers.values) {
                        controller.dispose();
                      }

                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("🎉 配置更新成功！已立即套用至系統。"),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text("儲存並套用", style: TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                ],
              );
            }
        );
      },
    );
  }

  /// 💡 自定義下拉選單組件
  Widget _buildDropdown(String label, String currentValue, List<Map<String, String>> options, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: DropdownButtonFormField<String>(
        value: currentValue,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: Colors.grey[50],
        ),
        items: options.map((option) {
          return DropdownMenuItem<String>(
            value: option['value'],
            child: Text(option['label']!, style: const TextStyle(fontSize: 14)),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  /// 自定義設定框組件
  Widget _buildSettingsField(
      String label,
      TextEditingController controller,
      String hint,
      bool obscureText,
      bool isSecure,
      VoidCallback onToggleVisibility,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: controller,
        obscureText: isSecure ? obscureText : false,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey),
          hintText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: isSecure
              ? IconButton(
            icon: Icon(
              obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18,
            ),
            onPressed: onToggleVisibility,
          )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double buttonWidth = screenWidth > 600 ? screenWidth * 0.35 : screenWidth * 0.75;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('首頁', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          // 語音快取管理按鈕
          IconButton(
            icon: const Icon(Icons.cleaning_services_rounded, color: Colors.black87),
            onPressed: () {
              context.push('/tts_cache_screen');
            },
            tooltip: "語音快取管理",
          ),
          // 回憶紀錄按鈕
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Colors.black87),
            onPressed: () {
              if (!_isConfigComplete()) {
                _showConfigWarning();
              } else {
                context.push('/history_screen');
              }
            },
            tooltip: "查看回憶紀錄",
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.black87),
            onPressed: _showSettingsDialog,
            tooltip: "設定 API 金鑰",
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 32.0,
            runSpacing: 40.0,
            children: [
              _buildHomeButton(
                context: context,
                imagePath: 'assets/images/life_home.png',
                width: buttonWidth,
                label: '以前的生活',
                routePath: '/life_screen',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeButton({
    required BuildContext context,
    required String imagePath,
    required double width,
    required String label,
    required String routePath,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            if (!_isConfigComplete()) {
              _showConfigWarning();
            } else {
              context.push(routePath);
            }
          },
          child: Container(
            width: width,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.grey.shade400,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22.5),
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: width * 0.8,
                    color: Colors.grey[200],
                    alignment: Alignment.center,
                    child: Text(
                      '$label\n(圖片遺失)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 20
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          label,
          style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4E342E)
          ),
        )
      ],
    );
  }
}