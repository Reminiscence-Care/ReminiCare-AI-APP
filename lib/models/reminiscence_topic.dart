enum ThumbnailStatus { idle, loading, ready, failed }

class TopicImageAttribution {
  const TopicImageAttribution({
    required this.title,
    required this.creator,
    required this.source,
    required this.license,
    required this.originalUrl,
    required this.licenseUrl,
  });

  final String title;
  final String creator;
  final String source;
  final String license;
  final String originalUrl;
  final String licenseUrl;

  Map<String, dynamic> toJson() => {
    'title': title,
    'creator': creator,
    'source': source,
    'license': license,
    'originalUrl': originalUrl,
    'licenseUrl': licenseUrl,
  };

  factory TopicImageAttribution.fromJson(Map<String, dynamic> json) =>
      TopicImageAttribution(
        title: (json['title'] ?? '').toString(),
        creator: (json['creator'] ?? '').toString(),
        source: (json['source'] ?? '').toString(),
        license: (json['license'] ?? '').toString(),
        originalUrl: (json['originalUrl'] ?? '').toString(),
        licenseUrl: (json['licenseUrl'] ?? '').toString(),
      );
}

class ReminiscenceTopic {
  const ReminiscenceTopic({
    required this.title,
    required this.question,
    required this.followUpQuestion,
    required this.imagePrompt,
    required this.imageSearchQuery,
    this.categoryId = 'other',
    this.thumbnailPath,
    this.thumbnailStatus = ThumbnailStatus.idle,
    this.thumbnailSourceId,
    this.thumbnailWidth,
    this.thumbnailHeight,
    this.thumbnailAttribution,
  });

  final String title;
  final String question;
  final String followUpQuestion;
  final String imagePrompt;
  final String imageSearchQuery;
  final String categoryId;
  final String? thumbnailPath;
  final ThumbnailStatus thumbnailStatus;
  final String? thumbnailSourceId;
  final int? thumbnailWidth;
  final int? thumbnailHeight;
  final TopicImageAttribution? thumbnailAttribution;

  static const _unset = Object();

  ReminiscenceTopic copyWith({
    Object? thumbnailPath = _unset,
    ThumbnailStatus? thumbnailStatus,
    Object? thumbnailSourceId = _unset,
    Object? thumbnailWidth = _unset,
    Object? thumbnailHeight = _unset,
    Object? thumbnailAttribution = _unset,
  }) => ReminiscenceTopic(
    title: title,
    question: question,
    followUpQuestion: followUpQuestion,
    imagePrompt: imagePrompt,
    imageSearchQuery: imageSearchQuery,
    categoryId: categoryId,
    thumbnailPath: identical(thumbnailPath, _unset)
        ? this.thumbnailPath
        : thumbnailPath as String?,
    thumbnailStatus: thumbnailStatus ?? this.thumbnailStatus,
    thumbnailSourceId: identical(thumbnailSourceId, _unset)
        ? this.thumbnailSourceId
        : thumbnailSourceId as String?,
    thumbnailWidth: identical(thumbnailWidth, _unset)
        ? this.thumbnailWidth
        : thumbnailWidth as int?,
    thumbnailHeight: identical(thumbnailHeight, _unset)
        ? this.thumbnailHeight
        : thumbnailHeight as int?,
    thumbnailAttribution: identical(thumbnailAttribution, _unset)
        ? this.thumbnailAttribution
        : thumbnailAttribution as TopicImageAttribution?,
  );

  factory ReminiscenceTopic.fromJson(Map<String, dynamic> json) {
    String value(String key) => (json[key] ?? '').toString().trim();
    final title = value('title');
    return ReminiscenceTopic(
      title: title,
      question: value('question'),
      followUpQuestion: value('followUpQuestion'),
      imagePrompt: value('imagePrompt'),
      imageSearchQuery: value('imageSearchQuery').isEmpty
          ? '$title Taiwan vintage photograph'
          : value('imageSearchQuery'),
      categoryId: value('categoryId').isEmpty ? 'other' : value('categoryId'),
    );
  }
}
