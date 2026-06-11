import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SearchOptions extends StatelessWidget {
  final String? languageLabel;
  const SearchOptions({super.key, this.languageLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '以前聽過的歌',
          style: TextStyle(fontSize: 16, color: Colors.black87),
        ),
      ),
      backgroundColor: Colors.white, // 確保背景是乾淨的白色
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start, // 讓所有元件在畫面上垂直居中
            crossAxisAlignment: CrossAxisAlignment.center, // 水平置中對齊
            children: [
              // 第二行文字 (語言標籤)
              SizedBox(height: 60),
              Text(
                languageLabel ?? '國語歌',
                style: const TextStyle(fontSize: 60, color: Colors.black87),
              ),
              const SizedBox(height: 160),

              // 第三行：兩個按鈕水平排列
              Row(
                mainAxisAlignment: MainAxisAlignment.center, // 讓兩個按鈕水平居中
                children: [
                  // 左邊按鈕：文字搜尋
                  TextButton(
                    onPressed: () {
                      context.push('/search_by_texts_or_speech/texts/$languageLabel');
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey[300], // 淺灰色背景
                      foregroundColor: Colors.black87, // 文字顏色
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6), // 圓角設定
                      ),
                    ),
                    child: const Text('文字搜尋', style: TextStyle(fontSize: 60)),
                  ),

                  const SizedBox(width: 40), // 兩個按鈕之間的水平間距

                  // 右邊按鈕：語音輸入 (帶有右側圖示)
                  TextButton(
                    onPressed: () {
                      context.push('/search_by_texts_or_speech/speech/$languageLabel');
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    // 使用 Row 來組合文字與圖示 (圖示靠右)
                    child: Row(
                      mainAxisSize: MainAxisSize.min, // 讓 Row 的寬度剛好包住內容
                      children: const [
                        Text('語音輸入', style: TextStyle(fontSize: 60)),
                        SizedBox(width: 8), // 文字與圖示的間距
                        Icon(Icons.mic, size: 60, color: Colors.black),
                      ],
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}