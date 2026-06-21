import 'package:remini_care_ai_app/services/api_services.dart';
import 'package:remini_care_ai_app/services/music_services/music_api_service.dart';
import 'package:remini_care_ai_app/services/llm_services/nvidia_llm_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeApiServices implements MusicApiService {
  Future<List<String>?> getArtistAndTracks(String query) async {
    final yt = YoutubeExplode();
    final llm = ApiServices().llm;
    print('正在搜尋 YouTube 關鍵字「$query」...\n');

    try {
      final searchResults = await yt.search.search(query);

      if (searchResults.isEmpty) {
        print('找不到任何相關結果');
        yt.close();
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

  Future<List<Map<String, String>>?> getTop5ArtistAndTracks(String query) async {
    final yt = YoutubeExplode();
    final llm = ApiServices().llm;
    print('正在搜尋 YouTube 關鍵字「$query」...\n');

    try {
      // 執行搜尋
      final searchResults = await yt.search.search(query);

      if (searchResults.isEmpty) {
        print('找不到任何相關結果');
        return [];
      }

      // 抓取前 5 筆結果（如果搜尋結果只有 3 筆，它也只會拿 3 筆，不會報錯）
      final topVideos = searchResults.take(5).toList();
      final List<Map<String, String>> finalSongsList = [];

      // 依序處理這 5 支影片
      for (var video in topVideos) {
        String artistName = video.author;
        String trackName = video.title;
        final String artistUrl = video.thumbnails.highResUrl;
        final String trackUrl = video.url;

        print('處理影片: $trackName');

        Map<String, dynamic> result = await llm.getSingerAndSongNameFromQuery("$artistName $trackName");

        if (result.isNotEmpty && result['singer'].toString().isNotEmpty) {
          artistName = result['singer'].toString();
        }
        if (result.isNotEmpty && result['song'].toString().isNotEmpty) {
          trackName = result['song'].toString();
        }

        finalSongsList.add({
          'artistName': artistName,
          'trackName': trackName,
          'artistUrl': artistUrl,
          'trackUrl': trackUrl,
        });
      }

      return finalSongsList;

    } catch (e) {
      print('發生錯誤: $e');
      return null;
    } finally {
      yt.close();
    }
  }
}