import 'package:remini_care_ai_app/services/music_services/music_api_service.dart';
import 'package:remini_care_ai_app/services/nvidia_llm_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeApiServices implements MusicApiService {
  Future<List<String>?> getArtistAndTracks(String query) async {
    final yt = YoutubeExplode();
    final llm = NvidiaLlmService();
    print('正在搜尋 YouTube 關鍵字「$query」...\n');

    try {
      // 執行搜尋，預設會回傳最相關的影片清單
      final searchResults = await yt.search.search(query);

      if (searchResults.isEmpty) {
        print('找不到任何相關結果');
        yt.close(); // 記得關閉釋放資源
        return [];
      }

      // 取得第一筆吻合的影片結果
      final video = searchResults.first;

      final List<String> searchResultsUrls = [];

      String artistName = video.author;
      print('頻道: $artistName');
      String trackName = video.title;
      print('標題: $trackName');



      final String artistUrl = video.thumbnails.highResUrl;
      print('縮圖: $artistUrl');
      final String trackUrl = video.url;
      print('網址: $trackUrl');

      Map<String, dynamic> result = await llm.getSingerAndSongNameFromQuery("$artistName $trackName");

      if(result.isNotEmpty && result['singer'].toString().isNotEmpty) {
        artistName = result['singer'].toString();
      }
      if(result.isNotEmpty && result['song'].toString().isNotEmpty){
        trackName = result['song'].toString();
      }
      searchResultsUrls.add(artistName);
      searchResultsUrls.add(trackName);
      searchResultsUrls.add(artistUrl);
      searchResultsUrls.add(trackUrl);
      yt.close();
      return searchResultsUrls;

    } catch (e) {
      print('發生錯誤: $e');
      yt.close();
      return null;
    }
  }
}