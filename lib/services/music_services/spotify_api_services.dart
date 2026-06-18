import 'package:remini_care_ai_app/services/music_services/music_api_service.dart';
import 'package:spotify/spotify.dart';

class SpotifyApiServices implements MusicApiService {
  String clientId;
  String clientSecret;
  SpotifyApiServices(this.clientId, this.clientSecret);

  Future<List<String>?> getArtistAndTracks(String query) async {
    final credentials = SpotifyApiCredentials(
        clientId,
        clientSecret
    );
    final spotify = SpotifyApi(credentials);

    final List? searchResults = await searchArtistAndTrack(spotify, query);

    if (searchResults == null) return null;
    if (searchResults.isEmpty) return [];

    final List<String> searchResultsUrls = [];

    final Artist? artist = searchResults[0] as Artist?;
    final artistId = artist?.id;
    final Track? track = searchResults[1] as Track?;
    final String? artistName = artist?.name;
    final String? trackName = track?.name;
    String? artistUrl;
    if(artistId != null) {
      final fullArtist = (await spotify.artists.get(artistId!));
      if(fullArtist.images != null && fullArtist.images!.isNotEmpty) {
        artistUrl = fullArtist.images!.first.url;
      }
    }
    final String? trackUrl = track?.externalUrls?.spotify;

    if (artistName != null) {
      searchResultsUrls.add(artistName);
      print(artistName);
    }
    if (trackName != null) {
      searchResultsUrls.add(trackName);
      print(trackName);
    }
    if (artistUrl != null) {
      searchResultsUrls.add(artistUrl);
      print(artistUrl);
    }
    if (trackUrl != null) {
      searchResultsUrls.add(trackUrl);
      print(trackUrl);
    }

    return searchResultsUrls;
  }

  Future<List?> searchArtistAndTrack(SpotifyApi spotify, String query) async {
    Artist? artist;
    Track? track;
    print('正在同時搜尋關鍵字「$query」的歌手與歌曲...\n');

    try {
      final searchPages = await spotify.search
          .get(query, types: [SearchType.track])
          .first(1);

      if (searchPages.isEmpty) {
        print('找不到任何相關結果');
        return [];
      }

      final page = searchPages.first;
      if (page.items == null || page.items!.isEmpty) {
        return [];
      }

      // 取得第一首吻合的歌曲
      final track = page.items!.first as Track;
      // 從這首歌的資料中，直接取出關聯的歌手 (ArtistSimple)
      final artist = (track.artists != null && track.artists!.isNotEmpty)
          ? track.artists!.first
          : null;

      // 回傳 [歌手, 歌曲]
      return [artist, track];
    } catch (e) {
      print('發生錯誤: $e');
      return null;
    }
  }
}
