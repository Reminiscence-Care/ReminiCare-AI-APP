import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double buttonWidth = screenWidth > 600 ? screenWidth * 0.35 : screenWidth * 0.75;

    return Scaffold(
      appBar: AppBar(
        title: const Text('首頁'),
        centerTitle: true,
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