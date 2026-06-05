import 'package:flutter/material.dart';

/// 1. 準備開始聊天視圖
class PrepareView extends StatelessWidget {
  final VoidCallback onStartChat;

  const PrepareView({super.key, required this.onStartChat});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey<String>("prepare_state"),
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

/// 2. 錄音進行中視圖 (包含即時秒數計時)
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
      key: const ValueKey<String>("listening_state"),
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
              '已錄音 : ${_formatDuration(recordSeconds)}',
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
              '結束錄音',
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

/// 3. 錄音/聊天完成視圖
class CompletedView extends StatelessWidget {
  final VoidCallback onRestartChat;
  final VoidCallback onEndChat;

  const CompletedView({
    super.key,
    required this.onRestartChat,
    required this.onEndChat,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>("completed_state"),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.grey[600], size: 24),
            const SizedBox(width: 8),
            Text(
              '聊天完成',
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey[800],
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 130,
              height: 48,
              child: TextButton(
                onPressed: onRestartChat,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  '重新聊天',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[800],
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(
              width: 130,
              height: 48,
              child: TextButton(
                onPressed: onEndChat,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey[400],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  '結束聊天',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
