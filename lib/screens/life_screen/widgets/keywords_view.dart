import 'package:flutter/material.dart';

/// 關鍵詞展示區（支援白底細粉灰框、與灰底的新增提示詞，完美貼合 image_69eb18）
class KeywordsView extends StatelessWidget {
  final bool isLoading;
  final List<String> originalKeywords;
  final List<String> newKeywords;
  final int maxLength;

  const KeywordsView({
    super.key,
    required this.isLoading,
    required this.originalKeywords,
    required this.newKeywords,
    required this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "AI 正在為您精準擷取關鍵詞...",
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              "提到的關鍵詞：",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 12.0,
              runSpacing: 10.0,
              children: [
                // 1. 原有的舊關鍵字 (白底細粉灰框)
                ...originalKeywords.map((word) => _buildKeywordChip(word, isNew: false)),
                // 2. 修改後新增的提示詞 (灰底框，呼應「提示灰色格是新的提示」)
                ...newKeywords.map((word) => _buildKeywordChip(word, isNew: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordChip(String word, {required bool isNew}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isNew ? Colors.grey[300] : const Color(0xFFFAF6F6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isNew ? Colors.grey[400]! : const Color(0xFFD4C9C9),
          width: 0.8,
        ),
      ),
      child: Text(
        word,
        style: TextStyle(
          fontSize: 15,
          color: Colors.grey[800],
          fontWeight: isNew ? FontWeight.bold : FontWeight.w400,
        ),
      ),
    );
  }
}

/// 關鍵字確認生圖按鈕
class KeywordsConfirmButton extends StatelessWidget {
  final bool isDisabled;
  final VoidCallback onConfirm;

  const KeywordsConfirmButton({
    super.key,
    required this.isDisabled,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 48,
      child: TextButton(
        onPressed: isDisabled ? null : onConfirm,
        style: TextButton.styleFrom(
          backgroundColor: Colors.grey[300],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          '確認生圖',
          style: TextStyle(
            fontSize: 16,
            color: isDisabled ? Colors.grey[400] : Colors.grey[800],
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}