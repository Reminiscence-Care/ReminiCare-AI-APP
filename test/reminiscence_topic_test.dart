import 'package:flutter_test/flutter_test.dart';
import 'package:remini_care_ai_app/models/reminiscence_topic.dart';

void main() {
  test('copyWith preserves topic content while updating thumbnail state', () {
    const topic = ReminiscenceTopic(
      title: '菜市場',
      question: '以前常去哪個市場？',
      followUpQuestion: '記得哪些聲音？',
      imagePrompt: 'old market',
      imageSearchQuery: '台灣 菜市場 | Taiwan market',
    );
    final ready = topic.copyWith(
      thumbnailPath: '/tmp/image.png',
      thumbnailStatus: ThumbnailStatus.ready,
    );
    expect(ready.title, topic.title);
    expect(ready.thumbnailPath, '/tmp/image.png');
    expect(ready.thumbnailStatus, ThumbnailStatus.ready);
  });
}
