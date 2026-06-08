import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:remini_care_ai_app/models/song_model.dart';

class AddSongsDataScreen extends StatefulWidget {
  const AddSongsDataScreen({super.key});

  @override
  State<StatefulWidget> createState() => _AddSongsDataScreenState();
}

class _AddSongsDataScreenState extends State<AddSongsDataScreen> {
  final TextEditingController _singerController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final List<String> _languageOptions = ['國語歌', '台語歌'];

  String? _savedImagePath;
  String? _savedAudioPath;

  String? _selectedLanguage;

  String _imageFileName = "尚未選擇圖片";
  String _audioFileName = "尚未選擇音樂";

  bool _isImageAutoLoaded = false;


  Future<void> _pickAndSaveFile({
    required FileType type,
    required Function(String path, String name) onSaved,
  }) async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: type,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      String originalPath = result.files.single.path!;
      String originalFileName = result.files.single.name;

      // 取得 App 的本機永久資料夾
      final docDir = await getApplicationSupportDirectory();

      // 例如原本叫 "葛蘭-我要你的愛.mp3"，在硬碟裡會變成 "1718000000.mp3"
      String safeExtension = p.extension(originalFileName); // 抓出 .mp3 或 .jpg
      String safeFileName = '${DateTime.now().millisecondsSinceEpoch}$safeExtension';
      String newPath = p.join(docDir.path, safeFileName);

      // 把剛剛選的檔案複製過去
      File originalFile = File(originalPath);
      await originalFile.copy(newPath);

      // 呼叫 callback 把新路徑存起來並更新畫面
      setState(() {
        String fileNameWithoutExtension = p.basenameWithoutExtension(originalFileName);
        List<String> patterned_string = fileNameWithoutExtension.split('-');
        if(type == FileType.audio) {
          // 如果可以直接從 file 提取出 <歌手名>-<歌名> 就直接更新
          if(patterned_string.length == 2){
            _singerController.text = patterned_string[0];
            _titleController.text = patterned_string[1];
          }
          // 如果可以直接從 file 提取出 <語言>-<年代>-<歌手名>-<歌名> 就直接更新
          else if(patterned_string.length == 4) {
            _selectedLanguage = patterned_string[0];
            if(_selectedLanguage!.contains("台語")) _selectedLanguage = _languageOptions[1];
            else _selectedLanguage = _languageOptions[0];
            _yearController.text = patterned_string[1];
            _singerController.text = patterned_string[2];
            _titleController.text = patterned_string[3];
          }
        }
        // 如果使用者在自動帶入後，又手動去選了新照片
        // 我們就要把自動帶入標記設為 false，避免打字時又被洗掉
        if (type == FileType.image) {
          _isImageAutoLoaded = false;
        }
        onSaved(newPath, originalFileName);
      });
    }
  }

  // 3. 核心：將資料打包寫入 Hive 資料庫
  void _saveToDatabase() {
    int? parsedYear = int.tryParse(_yearController.text.trim());
    if (_singerController.text.isEmpty ||
        _titleController.text.isEmpty ||
        _savedImagePath == null ||
        _savedAudioPath == null ||
        _selectedLanguage == null ||
        parsedYear == null
    ) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請填寫所有欄位並選擇圖片與音樂！')),
      );
      return;
    }

    // 建立要存進去的物件
    final newSong = SongModel(
      singer: _singerController.text,
      title: _titleController.text,
      imagePath: _savedImagePath!,
      audioPath: _savedAudioPath!,
      language: _selectedLanguage!,
      year: parsedYear,
    );

    // 打開箱子並丟進去！
    var box = Hive.box<SongModel>('my_music_box');
    box.add(newSong);

    // 顯示成功訊息並回到上一頁
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('歌曲已成功加入資料庫！')),
    );
    context.pop();
  }

  void _autoCheckExistingSinger() {
    String currentSingerName = _singerController.text.trim();
    if(currentSingerName.isEmpty) {
      if (_isImageAutoLoaded) {
        setState(() {
          _savedImagePath = null;
          _imageFileName = "尚未選擇圖片";
          _isImageAutoLoaded = false;
        });
      }
      return;
    }
    var box = Hive.box<SongModel>('my_music_box');
    SongModel? matchedSong;
    // 遍歷資料庫，尋找有沒有名字一模一樣的歌手
    for (var song in box.values) {
      if (song.singer.trim() == currentSingerName) {
        matchedSong = song;
        break; // 找到第一首就跳出
      }
    }
    // 如果找到歷史紀錄，且使用者目前「還沒有手動挑選新照片」
    if (matchedSong != null && (!_isImageAutoLoaded && _savedImagePath == null || _isImageAutoLoaded)) {
      setState(() {
        _savedImagePath = matchedSong!.imagePath;
        _imageFileName = "已自動帶入此歌手的歷史照片";
        _isImageAutoLoaded = true; // 標記為自動帶入
      });
    }
  }

  @override initState() {
    super.initState();
    _singerController.addListener(_autoCheckExistingSinger);
  }

  // 記得在離開頁面時釋放 Controller
  @override
  void dispose() {
    _singerController.removeListener(_autoCheckExistingSinger);
    _singerController.dispose();
    _titleController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新增歌曲')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500), // 防止在大螢幕上輸入框變得無限長
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- 語言分類選單 ---
                DropdownButtonFormField<String>(
                  value: _selectedLanguage,
                  decoration: const InputDecoration(
                    labelText: '歌曲語言分類',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.language),
                  ),
                  hint: const Text('請選擇國語歌或台語歌'),
                  items: _languageOptions.map((lang) {
                    return DropdownMenuItem(value: lang, child: Text(lang));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedLanguage = value;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // --- 年代 ---
                TextField(
                  controller: _yearController,
                  keyboardType: TextInputType.number, // 彈出數字小鍵盤
                  maxLength: 4, // 限制最多只能輸入 4 個數字
                  decoration: const InputDecoration(
                    labelText: '發行年份 (例如: 1978)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                    counterText: '', // 隱藏右下角的 0/4 字數提示
                  ),
                ),
                const SizedBox(height: 32),
                // --- 歌手輸入框 ---
                TextField(
                  controller: _singerController,
                  decoration: const InputDecoration(
                    labelText: '歌手名字',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),

                // --- 歌名輸入框 ---
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '歌曲名稱',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.music_note),
                  ),
                ),
                const SizedBox(height: 32),

                // --- 選擇圖片按鈕區塊 ---
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.image),
                      label: const Text('選擇封面圖片'),
                      onPressed: () {
                        _pickAndSaveFile(
                          type: FileType.image,
                          onSaved: (path, name) {
                            _savedImagePath = path;
                            _imageFileName = name;
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(_imageFileName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
                    ),
                  ],
                ),
                //如果抓到了路徑且檔案存在，直接秀出小預覽圖
                if (_savedImagePath != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(_savedImagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // --- 選擇音樂按鈕區塊 ---
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.audiotrack),
                      label: const Text('選擇音樂檔案'),
                      onPressed: () {
                        _pickAndSaveFile(
                          type: FileType.audio,
                          onSaved: (path, name) {
                            _savedAudioPath = path;
                            _audioFileName = name;
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                          _audioFileName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.grey)
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),

                // --- 儲存按鈕 ---
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB06A41), // 我們之前用的復古棕色
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _saveToDatabase, // 點擊時執行寫入資料庫邏輯
                    child: const Text('儲存至音樂庫'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}