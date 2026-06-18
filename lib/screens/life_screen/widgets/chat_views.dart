import 'package:flutter/material.dart';
import 'package:remini_care_ai_app/services/remini_care_config.dart';

/// 1. 準備開始聊天視圖 (一般對話用)
class PrepareView extends StatelessWidget {
  final VoidCallback onStartChat;

  const PrepareView({super.key, required this.onStartChat});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 48,
      child: TextButton(
        onPressed: onStartChat,
        style: TextButton.styleFrom(
          backgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          '開始聊天',
          textAlign: TextAlign.center,
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

/// 2. 錄音進行中視圖 (包含即時秒數計時，一般對話用)
class ListeningView extends StatelessWidget {
  final int recordSeconds;
  final VoidCallback onEndRecording;

  const ListeningView({
    super.key,
    required this.recordSeconds,
    required this.onEndRecording,
  });

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[300],
              ),
              alignment: Alignment.center,
              child: Text(
                '正在聆聽中',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '還剩 ${_formatDuration(recordSeconds)}/${ReminiCareConfig.maxRecordLimitM}:${ReminiCareConfig.maxRecordLimitS}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        const SizedBox(width: 40),
        SizedBox(
          width: 130,
          height: 48,
          child: TextButton(
            onPressed: onEndRecording,
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              '聊完了!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ],
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
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '還剩 ${_formatRemainingTime(recordSeconds)}',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 24),
            ElevatedButton(
              onPressed: onEndRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                '聊完了！',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: onCancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                '不想繼續聊',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 4. 進階準備視圖 (Like/Dislike 共用) - 重現截圖設計
class AdvancedPrepareView extends StatelessWidget {
  final VoidCallback onStartChat;

  const AdvancedPrepareView({super.key, required this.onStartChat});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 200,
          height: 56,
          child: ElevatedButton(
            onPressed: onStartChat,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD54F), // 黃色按鈕
              foregroundColor: Colors.black87,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Text(
              '點開始聊天',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '注意：只有${ReminiCareConfig.maxRecordLimitM}分鐘分享',
          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
        ),
      ],
    );
  }
}