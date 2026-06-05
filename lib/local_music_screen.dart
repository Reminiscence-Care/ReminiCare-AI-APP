import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:just_audio/just_audio.dart';

class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<File> _localSongs = [];
  File? _currentPlayingFile;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadLocalSongs();

    // 監聽播放狀態
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose(); // 離開頁面時釋放播放器
    super.dispose();
  }

  // 1. 讀取 App 專屬資料夾內的音樂
  Future<void> _loadLocalSongs() async {
    final docDir = await getApplicationDocumentsDirectory();
    final musicDir = Directory('${docDir.path}/my_music');

    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }

    final files = musicDir
        .listSync()
        .where((item) => item is File && (item.path.endsWith('.mp3') || item.path.endsWith('.wav')))
        .cast<File>()
        .toList();

    setState(() {
      _localSongs = files;
    });
  }

  // 2. 選取手機內的音樂並儲存
  Future<void> _pickAndSaveSong() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.audio,
    );

    if (result != null && result.files.single.path != null) {
      String originalPath = result.files.single.path!;
      String fileName = p.basename(originalPath);

      final docDir = await getApplicationDocumentsDirectory();
      String newPath = '${docDir.path}/my_music/$fileName';

      File originalFile = File(originalPath);
      await originalFile.copy(newPath);

      _loadLocalSongs(); // 重新整理列表

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功加入: $fileName')),
        );
      }
    }
  }

  // 3. 播放音樂
  Future<void> _playFile(File file) async {
    try {
      setState(() {
        _currentPlayingFile = file;
      });
      await _audioPlayer.setAudioSource(AudioSource.file(file.path));
      _audioPlayer.play();
    } catch (e) {
      debugPrint("播放錯誤: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的自訂音樂'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '從手機加入音樂',
            onPressed: _pickAndSaveSong,
          )
        ],
      ),
      body: Column(
        children: [
          // 列表區域
          Expanded(
            child: _localSongs.isEmpty
                ? const Center(child: Text('目前沒有音樂，請點擊右上角「+」加入'))
                : ListView.builder(
              itemCount: _localSongs.length,
              itemBuilder: (context, index) {
                File file = _localSongs[index];
                String fileName = p.basename(file.path);
                bool isCurrent = _currentPlayingFile?.path == file.path;

                return ListTile(
                  leading: const Icon(Icons.music_note),
                  title: Text(
                    fileName,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? Colors.blue : Colors.black,
                    ),
                  ),
                  onTap: () => _playFile(file),
                );
              },
            ),
          ),
          // 底部播放控制列
          if (_currentPlayingFile != null)
            Container(
              color: Colors.grey[200],
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '正在播放: ${p.basename(_currentPlayingFile!.path)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                      iconSize: 40,
                      color: Colors.blue,
                      onPressed: () {
                        if (_isPlaying) {
                          _audioPlayer.pause();
                        } else {
                          _audioPlayer.play();
                        }
                      },
                    )
                  ],
                ),
              ),
            )
        ],
      ),
    );
  }
}