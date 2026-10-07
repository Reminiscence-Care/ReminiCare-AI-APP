enum ConversationTurnKind { memory, correction }

class ConversationTurn {
  const ConversationTurn({
    required this.question,
    required this.text,
    required this.kind,
    required this.createdAt,
    this.imagePath = '',
  });
  final String question;
  final String text;
  final ConversationTurnKind kind;
  final DateTime createdAt;
  final String imagePath;
  Map<String, dynamic> toJson() => {
    'question': question,
    'text': text,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'imagePath': imagePath,
  };
}
