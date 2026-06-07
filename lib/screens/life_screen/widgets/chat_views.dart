import 'package:flutter/material.dart';
import 'language_selector.dart';

/// 1. 準備開始聊天視圖
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
              '結束錄音',
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.grey[600], size: 24),
            const SizedBox(width: 8),
            Text(
              '聊天完成',
              textAlign: TextAlign.center,
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
                  textAlign: TextAlign.center,
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
                  textAlign: TextAlign.center,
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

/// 4. 「不太像」進入修改準備視圖 (問：哪裡不對？) - 已修正寬螢幕拉太遠問題
class DislikePrepareView extends StatelessWidget {
  final String selectedLanguage;
  final ValueChanged<String> onLanguageSelected;
  final VoidCallback onStartChat;

  const DislikePrepareView({
    super.key,
    required this.selectedLanguage,
    required this.onLanguageSelected,
    required this.onStartChat,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550), // 限制最大寬度，避免在寬螢幕上兩側元件放太遠
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
                    isVertical: true,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      '哪裡不對？',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
            SizedBox(
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
            ),
          ],
        ),
      ),
    );
  }
}

/// 5. 「不太像」修改錄音進行中視圖 - 已修正寬螢幕拉太遠問題
class DislikeChattingView extends StatelessWidget {
  final String selectedLanguage;
  final ValueChanged<String> onLanguageSelected;
  final int recordSeconds;
  final VoidCallback onEndRecording;

  const DislikeChattingView({
    super.key,
    required this.selectedLanguage,
    required this.onLanguageSelected,
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
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550), // 限制最大寬度，確保錄音元件與左側語言選擇器靠近
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
                    isVertical: true,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      '哪裡不對？',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
            Row(
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
                      '結束錄音',
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
            ),
          ],
        ),
      ),
    );
  }
}

/// 6. 「像」延伸話題準備視圖 - 已修正寬螢幕拉太遠問題
class LikePrepareView extends StatelessWidget {
  final String selectedLanguage;
  final ValueChanged<String> onLanguageSelected;
  final VoidCallback onStartChat;

  const LikePrepareView({
    super.key,
    required this.selectedLanguage,
    required this.onLanguageSelected,
    required this.onStartChat,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550), // 限制最大寬度，保持視覺凝聚力
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
                    isVertical: true,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      '這張圖片讓您想到什麼？',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
            SizedBox(
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
            ),
          ],
        ),
      ),
    );
  }
}

/// 7. 「像」延伸話題錄音中視圖 - 已修正寬螢幕拉太遠問題
class LikeChattingView extends StatelessWidget {
  final String selectedLanguage;
  final ValueChanged<String> onLanguageSelected;
  final int recordSeconds;
  final VoidCallback onEndRecording;

  const LikeChattingView({
    super.key,
    required this.selectedLanguage,
    required this.onLanguageSelected,
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
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550), // 限制最大寬度
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
                    isVertical: true,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      '這張圖片讓您想到什麼？',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
            Row(
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
                      '結束錄音',
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
            ),
          ],
        ),
      ),
    );
  }
}