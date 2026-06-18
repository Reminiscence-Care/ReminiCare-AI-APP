import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SearchOptions extends StatelessWidget {
  final String? languageLabel;
  const SearchOptions({super.key, this.languageLabel});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;

    // 如果螢幕寬度小於 450，就判定它裝不下，改為上下排列
    final bool isSmallScreen = screenWidth < 450;

    // --- 文字搜尋按鈕 ---
    Widget textSearchButton = TextButton(
      onPressed: () {
        context.push('/search_by_texts_or_speech/texts/$languageLabel');
      },
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFFFDE065),
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('文字搜尋', style: TextStyle(fontSize: 40)),
      ),
    );

    // --- 語音輸入按鈕 ---
    Widget voiceSearchButton = TextButton(
      onPressed: () {
        context.push('/search_by_texts_or_speech/speech/$languageLabel');
      },
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFFFDE065),
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('語音輸入', style: TextStyle(fontSize: 40)),
            SizedBox(width: 8),
            Icon(Icons.mic, size: 40, color: Colors.black),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black, size: 40),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: size.height * 0.02),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '以前聽過的歌',
                    style: TextStyle(fontSize: (screenWidth * 0.08).clamp(26.0, 50.0), color: Colors.black87),
                  ),
                ),

                SizedBox(height: size.height * 0.05),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF59D),
                      borderRadius: BorderRadius.circular(8.0)
                  ),
                  child: Text(
                    languageLabel ?? '國語歌',
                    style: TextStyle(
                      fontSize: (screenWidth * 0.08).clamp(24.0, 40.0),
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                SizedBox(height: size.height * 0.15),

                // 根據螢幕大小決定要上下還是左右
                if (isSmallScreen)
                // 螢幕太小：上下排列 (Column)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch, // 讓按鈕填滿左右寬度
                    children: [
                      textSearchButton,
                      const SizedBox(height: 24), // 上下排列時的垂直間距
                      voiceSearchButton,
                    ],
                  )
                else
                // 螢幕夠大：左右排列 (Row)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(child: textSearchButton),
                      SizedBox(width: (screenWidth * 0.05).clamp(12.0, 40.0)), // 左右排列時的水平間距
                      Expanded(child: voiceSearchButton),
                    ],
                  ),

                SizedBox(height: size.height * 0.1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}