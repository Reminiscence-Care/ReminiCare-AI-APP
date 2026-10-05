import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/reminiscence_topic.dart';
import '../../../theme/remini_care_theme.dart';
import '../controllers/life_screen_controller.dart';

class ReminiCareViewport extends StatelessWidget {
  const ReminiCareViewport({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final contentWidth = math.max(constraints.maxWidth, 360.0);
      final contentHeight = math.max(constraints.maxHeight, 720.0);
      return ColoredBox(
        color: Colors.white,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            height: constraints.maxHeight,
            child: SingleChildScrollView(
              child: SizedBox(
                width: contentWidth,
                height: contentHeight,
                child: ColoredBox(color: Colors.white, child: child),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class LifeStageView extends StatelessWidget {
  const LifeStageView({
    super.key,
    required this.controller,
    required this.onDone,
  });
  final LifeScreenController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => switch (controller.stage) {
    LifeStage.topicLoading => const TopicLoadingStage(),
    LifeStage.topicSelection => TopicSelectionStage(controller: controller),
    LifeStage.introduction => IntroductionStage(controller: controller),
    LifeStage.question => QuestionStage(controller: controller),
    LifeStage.imageGenerating => const GeneratingStage(message: '正在把回憶變成照片…'),
    LifeStage.evaluation => EvaluationStage(controller: controller),
    LifeStage.revisionRecording => RevisionStage(controller: controller),
    LifeStage.revisionGenerating => const GeneratingStage(message: '正在調整照片…'),
    LifeStage.summary => SummaryStage(controller: controller, onDone: onDone),
  };
}

class TopicLoadingStage extends StatelessWidget {
  const TopicLoadingStage({super.key});
  @override
  Widget build(BuildContext context) => _StagePadding(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 72,
          height: 72,
          child: CircularProgressIndicator(
            strokeWidth: 7,
            color: ReminiCareTheme.yellow,
          ),
        ),
        const SizedBox(height: 36),
        Text(
          '正在準備今天的回憶主題',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: ReminiCareBreakpoints.actionSize(context)),
        ),
      ],
    ),
  );
}

class TopicSelectionStage extends StatelessWidget {
  const TopicSelectionStage({super.key, required this.controller});
  final LifeScreenController controller;

  @override
  Widget build(BuildContext context) {
    return _StagePadding(
      child: Column(
        children: [
          Text(
            '今天想聊什麼？',
            style: TextStyle(
              fontSize: ReminiCareBreakpoints.titleSize(context),
            ),
          ),
          if (controller.topicWarning != null ||
              controller.imageWarning != null) ...[
            const SizedBox(height: 12),
            _AiWarningBanner(
              topicWarning: controller.topicWarning,
              imageWarning: controller.imageWarning,
            ),
          ],
          const SizedBox(height: 28),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final phone =
                    constraints.maxWidth < ReminiCareBreakpoints.phone;
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: phone ? 1 : 4,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    childAspectRatio: phone ? 1.65 : .72,
                  ),
                  itemCount: controller.topics.length,
                  itemBuilder: (_, index) {
                    final topic = controller.topics[index];
                    return _TopicCard(
                      topic: topic,
                      onTap: () => controller.selectTopic(topic),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          _PillButton(label: '我想聊別的', onPressed: controller.refreshTopics),
        ],
      ),
    );
  }
}

class IntroductionStage extends StatelessWidget {
  const IntroductionStage({super.key, required this.controller});
  final LifeScreenController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.introductionState;
    return _StagePadding(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '請大家介紹自己',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ReminiCareBreakpoints.titleSize(context),
            ),
          ),
          const SizedBox(height: 34),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 18),
            decoration: BoxDecoration(
              color: ReminiCareTheme.paleYellow,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Text(
              controller.currentElderName.isEmpty
                  ? '我叫＿＿＿＿'
                  : '我叫 ${controller.currentElderName}',
              style: TextStyle(
                fontSize: ReminiCareBreakpoints.actionSize(context),
              ),
            ),
          ),
          const SizedBox(height: 52),
          if (state == IntroductionState.processing)
            const CircularProgressIndicator(color: ReminiCareTheme.yellow)
          else if (state == IntroductionState.confirmed)
            Wrap(
              spacing: 28,
              runSpacing: 18,
              alignment: WrapAlignment.center,
              children: [
                _RoundAction(
                  label: '下一位',
                  icon: Icons.group_add_rounded,
                  onPressed: controller.addNextParticipant,
                ),
                _RoundAction(
                  label: '開始聊天',
                  icon: Icons.chat_bubble_rounded,
                  onPressed: controller.finishIntroduction,
                ),
              ],
            )
          else
            _RoundAction(
              label: state == IntroductionState.recording ? '說完了' : '開始介紹',
              icon: state == IntroductionState.recording
                  ? Icons.stop_rounded
                  : Icons.mic_rounded,
              onPressed: state == IntroductionState.recording
                  ? controller.stopIntroductionRecording
                  : controller.startIntroductionRecording,
            ),
        ],
      ),
    );
  }
}

class QuestionStage extends StatelessWidget {
  const QuestionStage({super.key, required this.controller});
  final LifeScreenController controller;
  @override
  Widget build(BuildContext context) => _StagePadding(
    child: Column(
      children: [
        _LanguageSelector(controller: controller),
        const Spacer(),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 28),
          decoration: BoxDecoration(
            color: ReminiCareTheme.paleYellow,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Text(
            controller.currentQuestion,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ReminiCareBreakpoints.actionSize(context),
              height: 1.35,
            ),
          ),
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            controller.errorMessage!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 18),
          ),
        ],
        const Spacer(),
        if (controller.isRecording)
          Text(
            '錄音中 ${controller.recordSeconds} 秒',
            style: TextStyle(
              fontSize: ReminiCareBreakpoints.bodySize(context),
              color: ReminiCareTheme.muted,
            ),
          ),
        const SizedBox(height: 16),
        _RoundAction(
          label: controller.isRecording ? '說完了' : '開始說',
          icon: controller.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
          onPressed: controller.isRecording
              ? controller.stopAnswerRecording
              : controller.startAnswerRecording,
        ),
        const SizedBox(height: 18),
        TextButton(
          onPressed: controller.finishSession,
          child: const Text(
            '不想繼續聊',
            style: TextStyle(fontSize: 22, color: ReminiCareTheme.muted),
          ),
        ),
      ],
    ),
  );
}

class GeneratingStage extends StatelessWidget {
  const GeneratingStage({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => _StagePadding(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 84,
          height: 84,
          child: CircularProgressIndicator(
            strokeWidth: 8,
            color: ReminiCareTheme.yellow,
          ),
        ),
        const SizedBox(height: 38),
        Text(
          message,
          style: TextStyle(fontSize: ReminiCareBreakpoints.actionSize(context)),
        ),
      ],
    ),
  );
}

class EvaluationStage extends StatelessWidget {
  const EvaluationStage({super.key, required this.controller});
  final LifeScreenController controller;
  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < ReminiCareBreakpoints.tablet;
    final question = controller.hasExtension ? '這樣像嗎？' : '這張照片像您的回憶嗎？';
    final content = <Widget>[
      Expanded(child: _MemoryImage(path: controller.currentImagePath)),
      SizedBox(width: compact ? 0 : 46, height: compact ? 24 : 0),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LanguageSelector(controller: controller),
            const SizedBox(height: 32),
            Text(
              question,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ReminiCareBreakpoints.titleSize(context),
              ),
            ),
            const SizedBox(height: 46),
            Wrap(
              spacing: 24,
              runSpacing: 18,
              alignment: WrapAlignment.center,
              children: [
                _RoundAction(
                  label: '像',
                  icon: Icons.thumb_up_alt_rounded,
                  onPressed: controller.chooseLike,
                ),
                _RoundAction(
                  label: '不太像',
                  icon: Icons.tune_rounded,
                  onPressed: controller.chooseDislike,
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: controller.finishSession,
              child: const Text(
                '不想繼續聊',
                style: TextStyle(fontSize: 22, color: ReminiCareTheme.muted),
              ),
            ),
          ],
        ),
      ),
    ];
    return _StagePadding(
      child: compact ? Column(children: content) : Row(children: content),
    );
  }
}

class RevisionStage extends StatelessWidget {
  const RevisionStage({super.key, required this.controller});
  final LifeScreenController controller;
  @override
  Widget build(BuildContext context) => _StagePadding(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LanguageSelector(controller: controller),
        const Spacer(),
        Text(
          '哪裡不太像呢？',
          style: TextStyle(fontSize: ReminiCareBreakpoints.titleSize(context)),
        ),
        const SizedBox(height: 18),
        Text(
          controller.canEditImage ? '我會依照您的描述修改這張照片' : '目前的服務不支援原圖編輯，會重新產生一張照片',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: ReminiCareBreakpoints.bodySize(context),
            color: ReminiCareTheme.muted,
          ),
        ),
        if (controller.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              controller.errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 18),
            ),
          ),
        const Spacer(),
        if (controller.isRecording)
          Text(
            '錄音中 ${controller.recordSeconds} 秒',
            style: TextStyle(fontSize: ReminiCareBreakpoints.bodySize(context)),
          ),
        const SizedBox(height: 16),
        _RoundAction(
          label: controller.isRecording ? '說完了' : '開始說',
          icon: controller.isRecording ? Icons.stop_rounded : Icons.mic_rounded,
          onPressed: controller.isRecording
              ? controller.stopAnswerRecording
              : controller.startRevisionRecording,
        ),
      ],
    ),
  );
}

class SummaryStage extends StatelessWidget {
  const SummaryStage({
    super.key,
    required this.controller,
    required this.onDone,
  });
  final LifeScreenController controller;
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) {
    final phone = ReminiCareBreakpoints.isPhone(context);
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '今天的回憶',
          style: TextStyle(fontSize: ReminiCareBreakpoints.titleSize(context)),
        ),
        const SizedBox(height: 26),
        _SummaryLine(
          label: '主題',
          value: controller.selectedTopic?.title ?? '懷舊時光',
        ),
        _SummaryLine(
          label: '分享者',
          value: controller.elderNames.isEmpty
              ? '未留名'
              : controller.elderNames.join('、'),
        ),
        _SummaryLine(
          label: '關鍵字',
          value: controller.keywords.isEmpty
              ? '一起聊天的溫暖時光'
              : controller.keywords.join('、'),
        ),
      ],
    );
    return _StagePadding(
      child: Column(
        children: [
          Expanded(
            child: phone
                ? ListView(
                    children: [
                      info,
                      const SizedBox(height: 24),
                      _MemoryImage(path: controller.currentImagePath),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: 42),
                      Expanded(
                        child: _MemoryImage(path: controller.currentImagePath),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          _PillButton(
            label: '保存今天的回憶',
            onPressed: () async {
              await controller.saveMemory();
              onDone();
            },
          ),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic, required this.onTap});
  final ReminiscenceTopic topic;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 3,
    borderRadius: BorderRadius.circular(31),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(child: _Thumbnail(topic: topic)),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              topic.title,
              style: TextStyle(
                fontSize: ReminiCareBreakpoints.bodySize(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AiWarningBanner extends StatelessWidget {
  const _AiWarningBanner({this.topicWarning, this.imageWarning});
  final String? topicWarning;
  final String? imageWarning;

  @override
  Widget build(BuildContext context) {
    final messages = <String>[
      if (topicWarning != null) 'LLM 未成功，已使用本地題庫：$topicWarning',
    ];
    if (imageWarning case final warning?) messages.add(warning);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              messages.join('\n'),
              style: const TextStyle(fontSize: 16, color: Color(0xFF7A3E00)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.topic});
  final ReminiscenceTopic topic;
  @override
  Widget build(BuildContext context) {
    if (topic.thumbnailStatus == ThumbnailStatus.ready &&
        topic.thumbnailPath != null) {
      return _TopicImage(topic: topic);
    }
    if (topic.thumbnailStatus == ThumbnailStatus.loading) {
      return const ColoredBox(
        color: Color(0xFFF4F1E8),
        child: Center(
          child: CircularProgressIndicator(color: ReminiCareTheme.yellow),
        ),
      );
    }
    if (topic.thumbnailStatus == ThumbnailStatus.failed) {
      return const ColoredBox(
        color: Color(0xFFF1EFE9),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 54,
                color: Color(0xFF9E9A90),
              ),
              SizedBox(height: 10),
              Text(
                '暫時找不到圖片',
                style: TextStyle(fontSize: 16, color: Color(0xFF77736A)),
              ),
            ],
          ),
        ),
      );
    }
    return const ColoredBox(
      color: Color(0xFFF1EFE9),
      child: Center(
        child: Icon(Icons.photo_outlined, size: 62, color: Color(0xFFAAA69B)),
      ),
    );
  }
}

class _TopicImage extends StatelessWidget {
  const _TopicImage({required this.topic});
  final ReminiscenceTopic topic;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final path = topic.thumbnailPath!;
      final sourceRatio =
          (topic.thumbnailWidth ?? 0) > 0 && (topic.thumbnailHeight ?? 0) > 0
          ? topic.thumbnailWidth! / topic.thumbnailHeight!
          : 0.0;
      final targetRatio = constraints.maxHeight > 0
          ? constraints.maxWidth / constraints.maxHeight
          : 1.0;
      final closeRatio =
          sourceRatio > 0 &&
          ((sourceRatio - targetRatio).abs() / targetRatio) <= .12;
      return Stack(
        fit: StackFit.expand,
        children: [
          if (!closeRatio) ...[
            Transform.scale(
              scale: 1.08,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: _TopicImageFile(path: path, fit: BoxFit.cover),
              ),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: .08)),
          ],
          _TopicImageFile(
            path: path,
            fit: closeRatio ? BoxFit.cover : BoxFit.contain,
          ),
          if (topic.thumbnailAttribution != null)
            Positioned(
              top: 8,
              right: 8,
              child: _AttributionButton(
                attribution: topic.thumbnailAttribution!,
              ),
            ),
        ],
      );
    },
  );
}

class _TopicImageFile extends StatelessWidget {
  const _TopicImageFile({required this.path, required this.fit});
  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.file(
    File(path),
    fit: fit,
    gaplessPlayback: true,
    errorBuilder: (_, _, _) => const ColoredBox(
      color: Color(0xFFF1EFE9),
      child: Center(child: Icon(Icons.broken_image_outlined, size: 54)),
    ),
  );
}

class _AttributionButton extends StatelessWidget {
  const _AttributionButton({required this.attribution});
  final TopicImageAttribution attribution;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .58),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: '圖片來源與授權',
      visualDensity: VisualDensity.compact,
      color: Colors.white,
      icon: const Icon(Icons.info_outline_rounded, size: 22),
      onPressed: () => _showAttribution(context),
    ),
  );

  Future<void> _showAttribution(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('圖片來源與授權'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(attribution.title),
          const SizedBox(height: 12),
          Text('作者：${attribution.creator}'),
          Text('來源：${attribution.source}'),
          Text('授權：${attribution.license}'),
        ],
      ),
      actions: [
        if (_isSafeExternalUrl(attribution.licenseUrl))
          TextButton(
            onPressed: () => _open(attribution.licenseUrl),
            child: const Text('查看授權'),
          ),
        if (_isSafeExternalUrl(attribution.originalUrl))
          TextButton(
            onPressed: () => _open(attribution.originalUrl),
            child: const Text('查看原圖'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉'),
        ),
      ],
    ),
  );

  Future<void> _open(String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'https') {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  bool _isSafeExternalUrl(String value) =>
      Uri.tryParse(value)?.scheme == 'https';
}

class _MemoryImage extends StatelessWidget {
  const _MemoryImage({required this.path});
  final String path;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 4 / 3,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(31),
      child: path.isEmpty
          ? const ColoredBox(
              color: Color(0xFFF1EFE9),
              child: Icon(Icons.photo_outlined, size: 90),
            )
          : _LocalImage(path: path),
    ),
  );
}

class _LocalImage extends StatelessWidget {
  const _LocalImage({required this.path});
  final String path;
  @override
  Widget build(BuildContext context) {
    if (path.startsWith('http')) return Image.network(path, fit: BoxFit.cover);
    if (kIsWeb) {
      return const ColoredBox(
        color: Color(0xFFF1EFE9),
        child: Icon(Icons.photo_outlined),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xFFF1EFE9),
        child: Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.controller});
  final LifeScreenController controller;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    children: ['台語', '中文'].map((language) {
      final selected = controller.selectedLanguage == language;
      return ChoiceChip(
        label: Text(language, style: const TextStyle(fontSize: 21)),
        selected: selected,
        selectedColor: ReminiCareTheme.yellow,
        backgroundColor: ReminiCareTheme.languagePill,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        onSelected: (_) => controller.replayLanguage(language),
      );
    }).toList(),
  );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final FutureOr<void> Function() onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: SizedBox(
      width: 154,
      height: 154,
      child: FilledButton(
        onPressed: () => onPressed(),
        style: FilledButton.styleFrom(
          backgroundColor: ReminiCareTheme.yellow,
          foregroundColor: ReminiCareTheme.ink,
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(15),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onPressed});
  final String label;
  final FutureOr<void> Function() onPressed;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: () => onPressed(),
    style: FilledButton.styleFrom(
      backgroundColor: ReminiCareTheme.yellow,
      foregroundColor: ReminiCareTheme.ink,
      minimumSize: const Size(260, 70),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(37)),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w600),
    ),
  );
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Text(
      '$label：$value',
      style: TextStyle(
        fontSize: ReminiCareBreakpoints.bodySize(context),
        height: 1.45,
      ),
    ),
  );
}

class _StagePadding extends StatelessWidget {
  const _StagePadding({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: ReminiCareBreakpoints.isPhone(context) ? 20 : 52,
      vertical: 18,
    ),
    child: child,
  );
}
