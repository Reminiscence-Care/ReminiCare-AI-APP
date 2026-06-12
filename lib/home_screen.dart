import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// 引入金鑰管理器服務
import '../../services/reminicare_ai_services.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 💡 啟動時即在首頁默默加載本地金鑰配置，為稍後的使用做足準備！
    ReminiCareConfig.loadConfig();
  }

  // =========================================================================
  // ⚙️ 互動式自訂設定視窗 (💡 升級：完全由 ReminiCareConfig 宣告欄位動態渲染)
  // =========================================================================
  void _showSettingsDialog() {
    // 💡 1. 根據 ReminiCareConfig 宣告的 fields 清單，動態建立與映射 TextEditingController
    final Map<String, TextEditingController> controllers = {};
    for (var field in ReminiCareConfig.fields) {
      controllers[field.apiKey] = TextEditingController(
        text: ReminiCareConfig.getValue(field.apiKey),
      );
    }

    // 💡 2. 根據 fields 清單，動態建立眼睛遮罩 obscureText 狀態 (預設皆為遮罩 true)
    final Map<String, bool> obscureStates = {};
    for (var field in ReminiCareConfig.fields) {
      obscureStates[field.apiKey] = true;
    }

    showDialog(
      context: context,
      barrierDismissible: false, // 必須手動點按鈕關閉
      builder: (BuildContext context) {
        // 使用 StatefulBuilder 提供 Dialog 的局部 setState 狀態更新
        return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: const [
                    Icon(Icons.settings, color: Colors.blueGrey),
                    SizedBox(width: 8),
                    Text("ReminiCare AI 金鑰配置", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "金鑰儲存於您手機的本機安全資料庫中，您的機密不會外洩。設定完成後立即套用生效！",
                          style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                        ),
                        const SizedBox(height: 16),

                        // 💡 3. 完全動態生成欄位！不管有 5 個、6 個、10 個金鑰，此處 1 行程式碼全部自動建置
                        ...ReminiCareConfig.fields.map((field) {
                          final controller = controllers[field.apiKey]!;
                          final isObscured = obscureStates[field.apiKey] ?? true;

                          return _buildSettingsField(
                            field.displayName,
                            controller,
                            field.hintText,
                            isObscured,
                                () {
                              // 點擊右側小眼睛，動態切換單個輸入框的遮罩顯隱
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
                      // 安全釋放控制器內存，防範記憶體洩漏
                      for (var controller in controllers.values) {
                        controller.dispose();
                      }
                      Navigator.of(context).pop();
                    },
                    child: const Text("取消", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      // 💡 4. 動態收集所有 Controllers 當下的最新輸入值並寫入 Map
                      final Map<String, String> updatedData = {};
                      controllers.forEach((key, controller) {
                        updatedData[key] = controller.text;
                      });

                      // 💡 5. 一鍵永久儲存至本機快取與熱更替
                      await ReminiCareConfig.saveConfig(updatedData);

                      // 釋放內存
                      for (var controller in controllers.values) {
                        controller.dispose();
                      }

                      if (context.mounted) {
                        Navigator.of(context).pop();

                        // 貼心提示
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("🎉 金鑰更新成功！系統已立即載入新配置。"),
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

  /// 自定義設定框組件：支持動態控制密碼顯隱
  Widget _buildSettingsField(
      String label,
      TextEditingController controller,
      String hint,
      bool obscureText,
      VoidCallback onToggleVisibility,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        controller: controller,
        obscureText: obscureText, // 使用動態傳入的布林值
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey),
          hintText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: IconButton(
            // 依據 obscureText 的值動態更新眼睛圖示（開眼與閉眼）
            icon: Icon(
              obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18,
            ),
            onPressed: onToggleVisibility, // 觸發外界狀態更新
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double buttonWidth = screenWidth > 600 ? screenWidth * 0.35 : screenWidth * 0.75;

    return Scaffold(
      appBar: AppBar(
        title: const Text('首頁'),
        centerTitle: true,
        // 💡 頂部 AppBar 右側新增一個齒輪按鈕，方便使用者先在此設定好 API 金鑰，防範未然！
        actions: [
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
            spacing: 32.0, // 按鈕之間的水平間距
            runSpacing: 40.0, // 螢幕太窄換行時的垂直間距
            children: [

              // --- 1. 音樂功能按鈕 ---
              _buildHomeButton(
                context: context,
                imagePath: 'assets/images/music_home.png',
                width: buttonWidth,
                label: '以前愛聽的歌',
                routePath: '/music_screen',
              ),

              // --- 2. 生活功能按鈕 ---
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
      mainAxisSize: MainAxisSize.min, // 讓 Column 緊貼內容，不會無限延伸
      children: [
        GestureDetector(
          onTap: () {
            context.push(routePath);
          },
          child: Container(
            width: width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            // 圓角裁切與防呆機制
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain, // 確保圖片等比縮放
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