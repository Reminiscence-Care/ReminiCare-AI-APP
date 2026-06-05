import 'package:flutter/material.dart';

class KeywordsView extends StatelessWidget {
  final bool isLoading;
  final List<String> keywords;
  final int maxLength;

  const KeywordsView({
    super.key,
    required this.isLoading,
    required this.keywords,
    required this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Column(
        key: const ValueKey<String>("keywords_loading"),
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

    final displayKeywords = keywords.take(maxLength).toList();

    return Padding(
      key: const ValueKey<String>("keywords_loaded"),
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
              children: displayKeywords.map((keyword) => _buildKeywordChip(keyword)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordChip(String word) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF6F6),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: const Color(0xFFD4C9C9),
          width: 0.8,
        ),
      ),
      child: Text(
        word,
        style: TextStyle(
          fontSize: 15,
          color: Colors.grey[800],
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

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
      key: const ValueKey<String>("keywords_state_btn"),
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
