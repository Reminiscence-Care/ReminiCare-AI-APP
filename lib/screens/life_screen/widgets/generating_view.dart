import 'package:flutter/material.dart';

/// 取得根據螢幕寬度等比例縮放的字體大小 (限制在 24 ~ 40 之間)
double _getResponsiveFontSize(BuildContext context) {
  double screenWidth = MediaQuery.sizeOf(context).width;
  // 假設基準寬度約 400px 時，字體為 24
  double calculatedSize = screenWidth * 0.06;
  return calculatedSize.clamp(24.0, 40.0);
}

/// AI 生圖中的中置提示卡片組件
class GeneratingView extends StatelessWidget {
  const GeneratingView({super.key});

  @override
  Widget build(BuildContext context) {
    // 獲取動態字體大小
    double fontSize = _getResponsiveFontSize(context);

    // 💡 加入 Center 元件，確保卡片在任何螢幕大小下都能完美置中
    return Center(
      child: Container(
        // 根據字體大小動態調整 padding，讓卡片比例始終好看
        padding: EdgeInsets.symmetric(horizontal: fontSize * 2.0, vertical: fontSize * 1.2),
        decoration: BoxDecoration(
          color: const Color(0xFFD9D9D9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'AI生圖中',
              style: TextStyle(
                fontSize: fontSize, // 動態大標題
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                letterSpacing: 1.2,
              ),
            ),
            SizedBox(height: fontSize * 0.4), // 動態間距
            Text(
              '正在生成回憶照片...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize * 0.85, // 副標題稍微小一點，但一樣等比例縮放
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}