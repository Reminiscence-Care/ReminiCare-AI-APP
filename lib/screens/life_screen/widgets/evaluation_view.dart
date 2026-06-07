import 'package:flutter/material.dart';
import 'language_selector.dart';

/// 第一次生圖完成後的評價視圖 (像 / 不太像，完美貼合 image_8be021) - 已修正寬螢幕拉太遠問題
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
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550), // 限制最大寬度，確保在寬螢幕（MacBook）上元件保持集中
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
                  const SizedBox(width: 24),
                  Expanded(
                    child: Text(
                      '這張圖符合您的回憶嗎？',
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
              children: [
                _buildButton("像", onLike),
                const SizedBox(width: 24),
                _buildButton("不太像", onDislike),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: 130,
      height: 48,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
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

/// 第二次修改生圖完成後的評價視圖 (繼續修改圖 / 完成，完美貼合 image_69eb18)
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          height: 48,
          child: TextButton(
            onPressed: onContinueModify,
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              '繼續修改圖',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF424242),
                fontWeight: FontWeight.w500,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: 140,
          height: 48,
          child: TextButton(
            onPressed: onFinished,
            style: TextButton.styleFrom(
              backgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              '完成',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF424242),
                fontWeight: FontWeight.w500,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}