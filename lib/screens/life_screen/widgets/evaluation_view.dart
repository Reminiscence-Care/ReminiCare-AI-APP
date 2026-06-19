import 'package:flutter/material.dart';
import 'language_selector.dart';

/// 取得根據螢幕寬度等比例縮放的字體大小 (限制在 24 ~ 40 之間)
double _getResponsiveFontSize(BuildContext context) {
  double screenWidth = MediaQuery.sizeOf(context).width;
  // 假設基準寬度約 400px 時，字體為 24
  double calculatedSize = screenWidth * 0.06;
  return calculatedSize.clamp(24.0, 40.0);
}

/// 第一次生圖完成後的評價視圖 (像 / 不太像)
class EvaluationView extends StatelessWidget {
  final String selectedLanguage;
  final ValueChanged<String> onLanguageSelected;
  final VoidCallback onLike;
  final VoidCallback onDislike;

  const EvaluationView({
    super.key,
    required this.selectedLanguage,
    required this.onLanguageSelected,
    required this.onLike,
    required this.onDislike,
  });

  @override
  Widget build(BuildContext context) {
    double fontSize = _getResponsiveFontSize(context);

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        // 放寬最大寬度以容納長輩友善的超大字體
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  LanguageSelector(
                    selectedLanguage: selectedLanguage,
                    onLanguageSelected: onLanguageSelected,
                    isVertical: true, // 垂直排列
                  ),
                  SizedBox(width: fontSize), // 動態間距
                  Expanded(
                    child: Text(
                      '這張圖符合您的回憶嗎？',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: (fontSize * 1.1).clamp(24.0, 40.0), // 問題文字稍微放大
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: fontSize), // 動態間距
            Wrap(
              alignment: WrapAlignment.center,
              spacing: fontSize, // 動態水平間距
              runSpacing: fontSize * 0.5, // 換行時的動態垂直間距
              children: [
                _buildButton("像", onLike, fontSize),
                _buildButton("不太像", onDislike, fontSize),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed, double fontSize) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: Colors.grey[300],
        // 使用動態 padding 取代寫死的 width/height
        padding: EdgeInsets.symmetric(horizontal: fontSize * 1.5, vertical: fontSize * 0.8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(fontSize * 0.8), // 動態圓角
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.grey[800],
          fontWeight: FontWeight.w500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// 第二次修改生圖完成後的評價視圖 (繼續修改圖 / 完成)
class DislikeEvaluationView extends StatelessWidget {
  final VoidCallback onContinueModify;
  final VoidCallback onFinished;

  const DislikeEvaluationView({
    super.key,
    required this.onContinueModify,
    required this.onFinished,
  });

  @override
  Widget build(BuildContext context) {
    double fontSize = _getResponsiveFontSize(context);

    // 同樣改用 Wrap 避免按鈕爆版
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: fontSize,
      runSpacing: fontSize * 0.5,
      children: [
        TextButton(
          onPressed: onContinueModify,
          style: TextButton.styleFrom(
            backgroundColor: Colors.grey[300],
            padding: EdgeInsets.symmetric(horizontal: fontSize * 1.2, vertical: fontSize * 0.8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(fontSize * 0.8),
            ),
          ),
          child: Text(
            '繼續修改圖',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              color: const Color(0xFF424242),
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
            ),
          ),
        ),
        TextButton(
          onPressed: onFinished,
          style: TextButton.styleFrom(
            backgroundColor: Colors.grey[300],
            padding: EdgeInsets.symmetric(horizontal: fontSize * 1.2, vertical: fontSize * 0.8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(fontSize * 0.8),
            ),
          ),
          child: Text(
            '完成',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              color: const Color(0xFF424242),
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}