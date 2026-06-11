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
        context.push('/music_years_selection_screen/$languageLabel');
      },
      child: Container(
        width: width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // 加上淡淡的陰影讓圖片按鈕看起來有立體感
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        // 確保外層的圓角能完美裁切圖片
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            imagePath,
            fit: BoxFit.contain, // 圖片等比縮放不變形

            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: width * 0.8, // 給替代方塊一個合理的高度
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