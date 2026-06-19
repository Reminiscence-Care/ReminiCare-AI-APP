import 'package:flutter/material.dart';

/// 取得根據螢幕寬度等比例縮放的字體大小 (限制在 24 ~ 40 之間)
double _getResponsiveFontSize(BuildContext context) {
  double screenWidth = MediaQuery.sizeOf(context).width;
  // 假設基準寬度約 400px 時，字體為 24
  double calculatedSize = screenWidth * 0.06;
  return calculatedSize.clamp(24.0, 40.0);
}

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
    double fontSize = _getResponsiveFontSize(context);

    if (isVertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(context, "中文", fontSize),
          SizedBox(height: fontSize * 0.5),
          _buildOption(context, "台語", fontSize),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: fontSize * 1.5, // 動態水平間距 (取代原本寫死的 SizedBox)
      runSpacing: fontSize * 0.8, // 螢幕太窄自動換行時的垂直間距
      children: [
        _buildOption(context, "台語", fontSize),
        _buildOption(context, "中文", fontSize),
      ],
    );
  }

  Widget _buildOption(BuildContext context, String language, double fontSize) {
    final bool isSelected = selectedLanguage == language;
    return GestureDetector(
      onTap: () => onLanguageSelected(language),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: fontSize * 0.5, vertical: fontSize * 0.3),
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              // 圖示外圈跟著字體大小縮放
              width: fontSize * 1.5,
              height: fontSize * 1.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? Colors.grey[400] : Colors.grey[300],
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: fontSize, // 圖示大小跟著縮放
              ),
            ),
            SizedBox(width: fontSize * 0.5),
            Text(
              language,
              style: TextStyle(
                fontSize: fontSize,
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