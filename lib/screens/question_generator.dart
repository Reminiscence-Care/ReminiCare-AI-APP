import 'dart:math';

class TopicQuestionGenerator {
  // ==========================================
  // 🏡 以前的生活 (Life) 題庫
  // ==========================================
  static final List<String> _lifeQuestionList = [
    "小時候家裡最常吃什麼呢？",
    "以前家裡長什麼樣子呢？",
    "以前做家事最常做什麼呢？",
    "以前出門都怎麼去呢？",
    "小時候放學後最常做什麼呢？"
  ];

  static final List<String> _lifeSubQuestionList = [
    "是誰煮飯的？最喜歡吃什麼菜？",
    "家裡有幾個兄弟姊妹？夏天怎麼避暑？",
    "要幫忙洗衣服嗎？怎麼挑水？怎麼煮飯？",
    "走路還是騎腳踏車？第一次坐火車是什麼時候？",
    "要幫忙工作嗎？什麼時候才能出去玩？"
  ];

  // ==========================================
  // 🎵 以前愛聽的歌 (Music) 題庫
  // ==========================================
  static final List<String> _musicQuestionList = [
    "第一次聽到這首歌是在什麼時候？",
    "以前最喜歡的歌手是誰？",
    "家裡有人也喜歡嗎？",
    "以前大家都怎麼聽音樂？",
    "以前什麼場合最常聽到這首歌？",
    "年輕時有沒有特別會唱的歌？",
    "這首歌讓你想到以前的生活嗎？",
    "年輕時如果心情不好，會聽什麼歌？",
    "如果要介紹一首歌給年輕人，你會選哪一首？",
    "聽到這首歌，你最想跟大家分享什麼回憶？"
  ];

  static final List<String> _musicSubQuestionList = [
    "（幾歲的時候？在哪裡聽到？當時跟誰一起？）",
    "（為什麼喜歡他？長得帥嗎？漂亮嗎？）",
    "（收音機？唱片？錄音帶？廟會表演？）",
    "（父母？兄弟姊妹？另一半？好朋友？）",
    "（工作的時候？做家事的時候？結婚喜宴？廟會？）",
    "（KTV以前叫什麼？誰最會唱？有上台唱過嗎？）",
    "（那時候住哪裡？每天都在做什麼？跟現在有什麼不一樣？）",
    "（為什麼喜歡那首？有沒有特別的回憶？）",
    "（為什麼？想讓他們知道什麼故事？）",
    ""
  ];

  /// 隨機取得生活話題 (回傳格式: [大標題, 小標題])
  static List<String> generateLifeQuestion() {
    Random random = Random.secure();
    int result = random.nextInt(_lifeQuestionList.length);
    return [_lifeQuestionList[result], _lifeSubQuestionList[result]];
  }

  /// 隨機取得音樂話題 (回傳格式: [大標題, 小標題])
  static List<String> generateMusicQuestion() {
    Random random = Random.secure();
    int result = random.nextInt(_musicQuestionList.length);
    return [_musicQuestionList[result], _musicSubQuestionList[result]];
  }
}