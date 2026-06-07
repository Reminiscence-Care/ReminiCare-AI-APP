import 'package:flutter/material.dart';

/// 語言選擇組件（台語/中文播放按鈕），支援水平與垂直排列
class LanguageSelector extends StatelessWidget {
  final String selectedLanguage;
  final ValueChanged<String> onLanguageSelected;
  final bool isVertical; // 是否啟用垂直排列（用於評價與修改頁面）

  const LanguageSelector({
    super.key,
    required this.selectedLanguage,
    required this.onLanguageSelected,
    this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isVertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption("中文"),
          const SizedBox(height: 12),
          _buildOption("台語"),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildOption("台語"),
        const SizedBox(width: 48),
        _buildOption("中文"),
      ],
    );
  }

  Widget _buildOption(String language) {
    final bool isSelected = selectedLanguage == language;
    return GestureDetector(
      onTap: () => onLanguageSelected(language),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.grey[400] : Colors.grey[300],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              language,
              style: TextStyle(
                fontSize: 20,
                color: isSelected ? Colors.black : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}