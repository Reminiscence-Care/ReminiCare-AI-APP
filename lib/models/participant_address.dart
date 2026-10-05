/// Local correction options, never an automatic spelling replacement.
class ParticipantAddress {
  const ParticipantAddress(this.surname, this.title);
  final String surname;
  final String title;
  String get displayName => '$surname$title';

  static const titles = [
    '先生',
    '小姐',
    '女士',
    '長輩',
    '阿公',
    '阿嬤',
    '伯伯',
    '阿姨',
    '爺爺',
    '奶奶',
    '哥哥',
    '姊姊',
  ];
  static const _similarGroups = [
    ['余', '于', '俞', '於'],
    ['鍾', '鐘'],
    ['張', '章'],
    ['江', '姜'],
    ['楊', '陽'],
    ['蕭', '肖'],
    ['梁', '良'],
  ];
  static const commonSurnames = [
    '陳',
    '林',
    '黃',
    '張',
    '李',
    '王',
    '吳',
    '劉',
    '蔡',
    '楊',
    '許',
    '鄭',
    '謝',
    '郭',
    '洪',
    '邱',
    '曾',
    '廖',
    '賴',
    '徐',
    '周',
    '葉',
    '蘇',
    '莊',
    '呂',
    '江',
    '何',
    '蕭',
    '羅',
    '高',
    '余',
    '于',
    '俞',
    '於',
    '丁',
    '歐陽',
    '司馬',
    '上官',
    '諸葛',
  ];

  factory ParticipantAddress.fromDisplayName(String text) {
    for (final title in titles) {
      if (text.endsWith(title)) {
        return ParticipantAddress(
          text.substring(0, text.length - title.length),
          title,
        );
      }
    }
    return ParticipantAddress(text, '長輩');
  }

  static List<String> candidatesFor(String surname) {
    final candidates = <String>{surname};
    for (final group in _similarGroups) {
      if (group.contains(surname)) candidates.addAll(group);
    }
    return candidates.where((s) => s.isNotEmpty).toList();
  }

  // Manual confirmation permits rare surnames not present in the helper table.
  bool get isValid =>
      RegExp(r'^[\u3400-\u9fff]{1,4}$').hasMatch(surname) &&
      !titles.any(surname.endsWith) &&
      titles.contains(title);
}
