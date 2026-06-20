import 'package:flutter/material.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

/// 取得根據螢幕寬度等比例縮放的字體大小 (限制在 24 ~ 40 之間)
double _getResponsiveFontSize(BuildContext context) {
  double screenWidth = MediaQuery.sizeOf(context).width;
  // 假設基準寬度約 400px 時，字體為 24
  double calculatedSize = screenWidth * 0.06;
  return calculatedSize.clamp(24.0, 40.0);
}

/// 1. 準備開始聊天視圖 (一般對話用)
class PrepareView extends StatelessWidget {
  final VoidCallback onStartChat;

  const PrepareView({super.key, required this.onStartChat});

  @override
  Widget build(BuildContext context) {
    double fontSize = _getResponsiveFontSize(context);

    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity, // 💡 強迫撐滿寬度，讓內部的 Center 能夠發揮作用
        child: Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: onStartChat,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFDE065),
                padding: EdgeInsets.symmetric(horizontal: fontSize * 1.5, vertical: fontSize * 0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(fontSize),
                ),
              ),
              child: Text(
                '開始聊天',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fontSize,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2. 錄音進行中視圖 (包含即時秒數計時，一般對話用)
class ListeningView extends StatelessWidget {
  final int recordSeconds;
  final VoidCallback onEndRecording;

  const ListeningView({
    super.key,
    required this.recordSeconds,
    required this.onEndRecording,
  });

  String _formatTime() {
    int maxLimit = int.tryParse(ReminiCareConfig.maxRecordLimit) ?? 180;
    int remaining = maxLimit - recordSeconds;
    if (remaining < 0) remaining = 0;

    final minutes = (remaining ~/ 60).toString();
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    final maxMinutes = (maxLimit ~/ 60).toString();

    return "還剩$minutes:$seconds/$maxMinutes分鐘";
  }

  @override
  Widget build(BuildContext context) {
    double fontSize = _getResponsiveFontSize(context);

    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity, // 💡 強迫撐滿寬度
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: fontSize, // 動態水平間距
          runSpacing: fontSize * 0.8, // 換行垂直間距
          children: [
            // 左側：倒數計時框 (淺黃底 + 黃邊)
            Container(
              padding: EdgeInsets.symmetric(horizontal: fontSize * 1.2, vertical: fontSize * 0.6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9E6), // 淺黃色背景
                borderRadius: BorderRadius.circular(fontSize * 0.6), // 圓角適配
                border: Border.all(color: const Color(0xFFFFD54F), width: 1.5), // 黃色邊框
              ),
              child: Text(
                _formatTime(),
                style: TextStyle(
                  fontSize: fontSize,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // 右側：結束聊天按鈕 (實心黃底)
            ElevatedButton(
              onPressed: onEndRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black87,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: fontSize * 1.5, vertical: fontSize * 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(fontSize * 0.6),
                ),
              ),
              child: Text(
                '結束聊天',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3. 共用的新型倒數按鈕視圖 (取代 LikeChattingView 與 DislikeChattingView)
class AdvancedChattingControlView extends StatelessWidget {
  final int recordSeconds;
  final VoidCallback onEndRecording;
  final VoidCallback onCancel;

  const AdvancedChattingControlView({
    super.key,
    required this.recordSeconds,
    required this.onEndRecording,
    required this.onCancel,
  });

  String _formatRemainingTime(int elapsedSeconds) {
    int maxLimit = int.tryParse(ReminiCareConfig.maxRecordLimit) ?? 180;
    int remaining = maxLimit - elapsedSeconds;
    if (remaining < 0) remaining = 0;

    final minutes = (remaining ~/ 60).toString();
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    final maxMinutes = (maxLimit ~/ 60).toString();

    return "$minutes:$seconds/$maxMinutes分鐘";
  }

  @override
  Widget build(BuildContext context) {
    double fontSize = _getResponsiveFontSize(context);

    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity, // 💡 強迫撐滿寬度
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24.0,
          runSpacing: 24.0,
          children: [
            Text(
              '還剩 ${_formatRemainingTime(recordSeconds)}',
              style: TextStyle(
                fontSize: fontSize,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            ElevatedButton(
              onPressed: onEndRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(fontSize),
                ),
                padding: EdgeInsets.symmetric(horizontal: fontSize * 1.2, vertical: fontSize * 0.6),
              ),
              child: Text(
                '聊完了！',
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              onPressed: onCancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(fontSize),
                ),
                padding: EdgeInsets.symmetric(horizontal: fontSize * 1.2, vertical: fontSize * 0.6),
              ),
              child: Text(
                '不想繼續聊',
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 4. 進階準備視圖 (Like/Dislike/下一個長輩 共用) - 黃色大按鈕
class AdvancedPrepareView extends StatelessWidget {
  final VoidCallback onStartChat;

  const AdvancedPrepareView({super.key, required this.onStartChat});

  @override
  Widget build(BuildContext context) {
    double fontSize = _getResponsiveFontSize(context);

    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity, // 💡 強迫撐滿寬度
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center, // 💡 確保 Column 內元件居中
          children: [
            ElevatedButton(
              onPressed: onStartChat,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F), // 黃色按鈕
                foregroundColor: Colors.black87,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: fontSize * 1.5, vertical: fontSize * 0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(fontSize),
                ),
              ),
              child: Text(
                '點開始聊天',
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '注意：只有${ReminiCareConfig.maxRecordLimitM}分鐘分享',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: (fontSize * 0.9).clamp(24.0, 40.0),
                  color: Colors.grey[700]
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 5. 單一話題結束後的選項：繼續聊天 或 完成今天
class RoundSummaryControls extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onFinish;

  const RoundSummaryControls({super.key, required this.onContinue, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    double fontSize = _getResponsiveFontSize(context);

    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity, // 💡 強迫撐滿寬度
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 24.0,
          runSpacing: 24.0,
          children: [
            ElevatedButton(
              onPressed: onContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(fontSize)),
                padding: EdgeInsets.symmetric(horizontal: fontSize * 1.2, vertical: fontSize * 0.6),
              ),
              child: Text('繼續聊天', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: onFinish,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(fontSize)),
                padding: EdgeInsets.symmetric(horizontal: fontSize * 1.2, vertical: fontSize * 0.6),
              ),
              child: Text('完成今天聊天', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}