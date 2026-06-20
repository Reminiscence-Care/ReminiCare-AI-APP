import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // 💡 讀取紀錄 (修正 Key 為 chat_memories 確保與 LifeScreen 寫入一致)
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> savedList = prefs.getStringList('chat_memories') ?? [];

    setState(() {
      // 反轉陣列讓最新的紀錄排在最上面
      _records = savedList.map((e) => jsonDecode(e) as Map<String, dynamic>).toList().reversed.toList();
      _isLoading = false;
    });
  }

  // 💡 刪除紀錄
  Future<void> _deleteRecord(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> savedList = prefs.getStringList('chat_memories') ?? [];

    // 因為 _records 是反轉過的，所以要推算回原本在 savedList 中的真實索引
    final int originalIndex = _records.length - 1 - index;

    if (originalIndex >= 0 && originalIndex < savedList.length) {
      savedList.removeAt(originalIndex);
      await prefs.setStringList('chat_memories', savedList);

      setState(() {
        _records.removeAt(index);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已刪除該筆回憶紀錄'), backgroundColor: Colors.grey),
        );
      }
    }
  }

  // 💡 刪除前的確認視窗
  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 8),
            Text("刪除回憶", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text("確定要刪除這筆回憶紀錄嗎？\n刪除後將無法復原喔！", style: TextStyle(fontSize: 16, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消", style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteRecord(index); // 確認刪除
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("確定刪除", style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          "回憶紀錄",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _records.isEmpty
          ? const Center(
        child: Text(
          "目前還沒有回憶紀錄喔！\n快去跟長輩們聊聊天吧～",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: Colors.grey, height: 1.5),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _records.length,
        itemBuilder: (context, index) {
          final record = _records[index];
          return _buildRecordCard(record, index);
        },
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record, int index) {
    final String date = record['date'] ?? '';
    final String topic = record['topic'] ?? '';
    final String content = record['content'] ?? '';
    final String elders = record['elders'] ?? '';
    final String imagePath = record['imagePath'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      clipBehavior: Clip.antiAlias, // 讓 InkWell 的水波紋不會超出圓角
      child: InkWell(
        // 💡 點擊卡片跳轉至詳細頁面
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MemoryDetailScreen(record: record),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側縮圖
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[200],
                ),
                clipBehavior: Clip.antiAlias,
                child: imagePath.isNotEmpty
                    ? (imagePath.startsWith('http') || imagePath.startsWith('https')
                    ? Image.network(imagePath, fit: BoxFit.cover)
                    : (kIsWeb ? const Center(child: Icon(Icons.image, color: Colors.grey)) : Image.file(File(imagePath), fit: BoxFit.cover)))
                    : const Center(child: Icon(Icons.image, size: 32, color: Colors.grey)),
              ),
              const SizedBox(width: 16),

              // 右側文字資訊
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            topic,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 💡 日期與刪除按鈕
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(date, style: TextStyle(fontSize: 14, color: Colors.grey[500], fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _confirmDelete(index),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                                child: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                              ),
                            )
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "參與者：$elders",
                      style: TextStyle(fontSize: 14, color: Colors.blueGrey[700], fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      content,
                      style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ==========================================
// 🌟 點擊後的詳細展示頁面 (完美繼承 LifeScreen 的排版邏輯)
// ==========================================
class MemoryDetailScreen extends StatelessWidget {
  final Map<String, dynamic> record;

  const MemoryDetailScreen({super.key, required this.record});

  double _getResponsiveFontSize(BuildContext context) {
    double screenWidth = MediaQuery.sizeOf(context).width;
    double calculatedSize = screenWidth * 0.06;
    return calculatedSize.clamp(24.0, 40.0);
  }

  @override
  Widget build(BuildContext context) {
    final String topic = record['topic'] ?? '懷舊時光';
    final String content = record['content'] ?? '';
    final String elders = record['elders'] ?? '未留名';
    final String imagePath = record['imagePath'] ?? '';
    final String date = record['date'] ?? '';

    double fontSize = _getResponsiveFontSize(context);
    double screenWidth = MediaQuery.sizeOf(context).width;
    bool isWideScreen = screenWidth >= 800;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.grey[200],
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black, size: fontSize),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200), // 💡 放寬最大寬度極限，徹底利用螢幕閒置空間
            child: Container(
              width: double.infinity,
              margin: EdgeInsets.all(fontSize),
              padding: EdgeInsets.symmetric(vertical: fontSize * 2.0, horizontal: fontSize * 2.5), // 💡 加大左右內距，讓排版更飽滿
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 標題與日期
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 600),
                    padding: EdgeInsets.symmetric(vertical: fontSize * 0.8),
                    decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(fontSize * 2)),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Text("回憶詳細資料", style: TextStyle(fontSize: fontSize * 1.1, fontWeight: FontWeight.bold, color: Colors.black87)),
                        SizedBox(height: fontSize * 0.2),
                        Text(date, style: TextStyle(fontSize: fontSize * 0.7, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  SizedBox(height: fontSize * 2.5),

                  // 響應式排版 (大螢幕左右，小螢幕上下)
                  if (isWideScreen)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3, // 💡 把比例改為 3:2，給予文字高達 60% 的充裕空間
                          child: _buildMemoryTextInfo(topic, content, elders, fontSize),
                        ),
                        SizedBox(width: fontSize * 2),
                        Expanded(
                          flex: 2, // 💡 圖片佔 40% 的空間即可
                          child: _buildMemoryImage(imagePath, fontSize),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _buildMemoryTextInfo(topic, content, elders, fontSize),
                        SizedBox(height: fontSize * 2.0),
                        _buildMemoryImage(imagePath, fontSize),
                      ],
                    ),

                  SizedBox(height: fontSize * 3.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemoryTextInfo(String topic, String content, String elders, double fontSize) {
    return Column(
      children: [
        _buildSummaryRow("主題：", topic, fontSize),
        _buildSummaryRow("內容：", content, fontSize),
        _buildSummaryRow("分享者：", elders, fontSize),
      ],
    );
  }

  Widget _buildMemoryImage(String imagePath, double fontSize) {
    return AspectRatio(
      aspectRatio: 4 / 3, // 維持懷舊照片的 4:3 比例
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.grey[200],
        ),
        clipBehavior: Clip.antiAlias,
        child: imagePath.isNotEmpty
            ? (imagePath.startsWith('http') || imagePath.startsWith('https')
            ? Image.network(imagePath, fit: BoxFit.cover)
            : (kIsWeb ? Center(child: Text('Web 無法預覽', style: TextStyle(color: Colors.grey, fontSize: fontSize*0.6))) : Image.file(File(imagePath), fit: BoxFit.cover)))
            : Center(child: Icon(Icons.image, size: fontSize * 2, color: Colors.grey)),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, double fontSize) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: fontSize * 0.6), // 💡 增加行距
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: fontSize * 4.2, // 💡 縮小標籤的固定寬度，把空間還給內文
              padding: EdgeInsets.symmetric(vertical: fontSize * 0.4),
              decoration: BoxDecoration(color: const Color(0xFFFFF9E6), borderRadius: BorderRadius.circular(fontSize)),
              alignment: Alignment.center,
              child: Text(label, style: TextStyle(fontSize: fontSize * 0.85, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ),
            SizedBox(width: fontSize * 1.2),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: fontSize * 0.25), // 💡 頂部稍微向下推以對齊標籤中心
                child: Text(value, style: TextStyle(fontSize: fontSize * 0.95, color: Colors.black87, height: 1.4), textAlign: TextAlign.left),
              ),
            ),
          ]
      ),
    );
  }
}