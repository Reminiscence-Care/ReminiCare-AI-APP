import 'package:flutter/material.dart';

class QuestionArea extends StatelessWidget {
  final String questionText;

  const QuestionArea({super.key, required this.questionText});

  @override
  Widget build(BuildContext context) {
    if (questionText.isEmpty) {
      return Container(
        key: const ValueKey<String>("placeholder"),
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
      key: ValueKey<String>(questionText),
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

class QuestionLoadingIndicator extends StatelessWidget {
  const QuestionLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>("loading"),
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