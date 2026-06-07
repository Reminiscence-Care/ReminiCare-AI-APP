import 'package:flutter/material.dart';

/// 中央 AI 問題文字區域或預留的佔位提示
class QuestionArea extends StatelessWidget {
  final String questionText;

  const QuestionArea({super.key, required this.questionText});

  @override
  Widget build(BuildContext context) {
    if (questionText.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          "等待 AI 產生問題中...",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
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
        style: const TextStyle(
          fontSize: 28,
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