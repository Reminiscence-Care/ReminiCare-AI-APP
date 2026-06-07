import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MusicYearsSelectionScreen extends StatelessWidget {
  final String? musicLanguage;

  const MusicYearsSelectionScreen({
    super.key,
    this.musicLanguage
  });

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double buttonWidth = screenWidth > 600 ? screenWidth * 0.2 : screenWidth * 0.3;

    return Scaffold(
      appBar: AppBar(
        title: Text(musicLanguage ?? '選擇年代'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上方大標題
              const Padding(
                padding: EdgeInsets.only(bottom: 40.0),
                child: Text(
                  '以前愛聽的歌',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
              ),

              Wrap(
                alignment: WrapAlignment.center,
                spacing: 24.0, // 按鈕之間的水平間距
                runSpacing: 24.0, // 換行時的垂直間距
                children: [

                  // --- 1950-1960 年代按鈕 ---
                  _buildYearButton(
                    context: context,
                    imagePath: 'assets/images/1950.png',
                    width: buttonWidth,
                    yearLabel: '1950-1960',
                  ),

                  // --- 1960-1970 年代按鈕 ---
                  _buildYearButton(
                    context: context,
                    imagePath: 'assets/images/1960.png',
                    width: buttonWidth,
                    yearLabel: '1960-1970',
                  ),

                  // --- 1970-1980 年代按鈕 ---
                  _buildYearButton(
                    context: context,
                    imagePath: 'assets/images/1970.png',
                    width: buttonWidth,
                    yearLabel: '1970-1980',
                  ),

                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYearButton({
    required BuildContext context,
    required String imagePath,
    required double width,
    required String yearLabel,
  }) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('即將播放 $musicLanguage $yearLabel 年代的歌')),
        );
        context.push('/select_songs_screen/$musicLanguage/$yearLabel');
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
        // 確保外層的圓角能套用到圖片
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            imagePath,
            fit: BoxFit.contain, // 讓圖片等比縮放不變形

            // 防呆機制：圖片還沒放進去時的替代畫面
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: width, // 弄成正方形
                color: Colors.brown[100],
                alignment: Alignment.center,
                child: Text(
                  '$yearLabel\n(請放入圖片)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.brown, fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}