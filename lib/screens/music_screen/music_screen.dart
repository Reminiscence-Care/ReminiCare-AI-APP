import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MusicScreen extends StatelessWidget {
  const MusicScreen ({super.key});

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double buttonWidth = screenWidth > 600 ? screenWidth * 0.25 : screenWidth * 0.5;

    return Scaffold(
      appBar: AppBar(
        title: const Text('音樂'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 40.0),
                child: Text(
                  '想聽什麼歌呢？',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
              Column(
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 32.0, // 按鈕之間的水平間距
                    runSpacing: 32.0, // 螢幕太窄被擠到下一行時的垂直間距
                    children: [
                      // --- 國語歌按鈕 ---
                      _buildLanguageButton(
                        context: context,
                        imagePath: 'assets/images/mandarin_songs.png',
                        width: buttonWidth,
                        languageLabel: '國語歌',
                      ),

                      // --- 台語歌按鈕 ---
                      _buildLanguageButton(
                        context: context,
                        imagePath: 'assets/images/taiwanese_songs.png',
                        width: buttonWidth,
                        languageLabel: '台語歌',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageButton({
    required BuildContext context,
    required String imagePath,
    required double width,
    required String languageLabel,
  }) {
    return GestureDetector(
      onTap: () {
        context.push('/search_and_recommendation/$languageLabel');
      },
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: Colors.white, // 加上白底防護
          borderRadius: BorderRadius.circular(24), // 加大圓角至 24
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
        // 內層圓角設為 22.5，確保圖片裁切不會蓋到外框
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22.5),
          child: Image.asset(
            imagePath,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: width * 0.8,
                color: Colors.blueGrey[50],
                alignment: Alignment.center,
                child: Text(
                  '$languageLabel\n(圖片遺失)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.blueGrey,
                      fontWeight: FontWeight.bold,
                      fontSize: 22
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}