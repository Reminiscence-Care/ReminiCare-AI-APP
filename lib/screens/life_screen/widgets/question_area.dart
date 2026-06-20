import 'package:flutter/material.dart';

/// 取得根據螢幕寬度等比例縮放的字體大小 (限制在 24 ~ 40 之間)
double _getResponsiveFontSize(BuildContext context) {
  double screenWidth = MediaQuery.sizeOf(context).width;
  double calculatedSize = screenWidth * 0.06;
  return calculatedSize.clamp(24.0, 40.0);
}

/// 中央 AI 問題文字區域 (支援大標題與小副標題)
class QuestionArea extends StatelessWidget {
  final String mainText;
  final String subText;

  const QuestionArea({
    super.key,
    required this.mainText,
    this.subText = "",
  });

  @override
  Widget build(BuildContext context) {
    double fontSize = _getResponsiveFontSize(context);

    if (mainText.isEmpty) {
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 大標題
          Text(
            mainText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold, // 主標題加粗
              color: Colors.black,
              height: 1.5,
              letterSpacing: 1.0,
            ),
          ),
          // 小副標題 (如果有內容的話)
          if (subText.isNotEmpty) ...[
            SizedBox(height: fontSize * 0.4),
            Text(
              subText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: (fontSize * 0.75).clamp(20.0, 32.0), // 副標題等比例縮小
                fontWeight: FontWeight.w400,
                color: Colors.grey[700],
                height: 1.5,
                letterSpacing: 1.0,
              ),
            ),
          ]
        ],
      ),
    );
  }
}

/// 問題加載中的指示器
class QuestionLoadingIndicator extends StatelessWidget {
  const QuestionLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
        ),
      ),
    );
  }
}