import 'package:flutter/material.dart';

/// 取得根據螢幕寬度等比例縮放的字體大小 (限制在 24 ~ 40 之間)
double _getResponsiveFontSize(BuildContext context) {
  double screenWidth = MediaQuery.sizeOf(context).width;
  // 假設基準寬度約 400px 時，字體為 24
  double calculatedSize = screenWidth * 0.06;
  return calculatedSize.clamp(24.0, 40.0);
}

/// 中央 AI 問題文字區域或預留的佔位提示
class QuestionArea extends StatelessWidget {
  final String questionText;

  const QuestionArea({super.key, required this.questionText});

  @override
  Widget build(BuildContext context) {
    double fontSize = _getResponsiveFontSize(context);

    if (questionText.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          "等待 AI 產生問題中...",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w300,
            color: Colors.grey[400],
            height: 1.5,
            letterSpacing: 1.0,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        questionText,
        textAlign: TextAlign.center,
        style: TextStyle(
          // AI 正式產生的問題，字體稍微放大一點以強調重點，但也受限於最大 40
          fontSize: (fontSize * 1.1).clamp(24.0, 40.0),
          fontWeight: FontWeight.w400,
          color: Colors.black,
          height: 1.5,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

/// 問題加載中的指示器
class QuestionLoadingIndicator extends StatelessWidget {
  const QuestionLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    double fontSize = _getResponsiveFontSize(context);

    return Container(
      height: fontSize * 2, // 根據字體大小調整 loading 容器高度
      alignment: Alignment.center,
      child: SizedBox(
        // Loading 圈圈也跟著字體大小等比縮放
        width: fontSize,
        height: fontSize,
        child: const CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
        ),
      ),
    );
  }
}