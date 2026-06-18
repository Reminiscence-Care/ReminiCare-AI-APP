import 'package:remini_care_ai_app/services/music_services/music_api_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeApiServices implements MusicApiService {
  YoutubeApiServices();

  Future<List<String>?> getArtistAndTracks(String query) async {
    final yt = YoutubeExplode();
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

      final String artistName = video.author;
      searchResultsUrls.add(artistName);
      print('頻道: $artistName');

      final String trackName = video.title;
      searchResultsUrls.add(trackName);
      print('標題: $trackName');

      final String artistUrl = video.thumbnails.highResUrl;
      searchResultsUrls.add(artistUrl);
      print('縮圖: $artistUrl');

      final String trackUrl = video.url;
      searchResultsUrls.add(trackUrl);
      print('網址: $trackUrl');

      yt.close();
      return searchResultsUrls;

    } catch (e) {
      print('發生錯誤: $e');
      yt.close();
      return null;
    }
  }
}