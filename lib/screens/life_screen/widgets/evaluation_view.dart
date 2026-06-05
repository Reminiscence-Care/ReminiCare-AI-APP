import 'package:flutter/material.dart';
import 'language_selector.dart';

class EvaluationView extends StatelessWidget {
  final String selectedLanguage;
  final ValueChanged<String> onLanguageSelected;
  final String imageUrl;
  final VoidCallback onLike;
  final VoidCallback onDislike;

  const EvaluationView({
    super.key,
    required this.selectedLanguage,
    required this.onLanguageSelected,
    required this.imageUrl,
    required this.onLike,
    required this.onDislike,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. 生成完畢的照片
        Container(
          width: 320,
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey[200],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // 2. 垂直排列語言選擇器 與 回憶詢問語並排 (完美還原 image_8be021 視覺排版)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 左側：垂直擺放的語言選擇器
              LanguageSelector(
                selectedLanguage: selectedLanguage,
                onLanguageSelected: onLanguageSelected,
              ),
              const SizedBox(width: 24),
              // 右側：高對比問句
              const Expanded(
                child: Text(
                  '這張圖符合您的回憶嗎？',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 3. 底部「像」與「不太像」確認按鈕
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildButton("像", onLike),
            const SizedBox(width: 24),
            _buildButton("不太像", onDislike),
          ],
        ),
      ],
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: 130,
      height: 48,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[800],
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
