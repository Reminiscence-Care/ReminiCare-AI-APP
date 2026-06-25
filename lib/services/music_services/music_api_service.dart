abstract class MusicApiService {
  /*
   input: 關鍵字
   output: [歌手/頻道名, 歌曲/影片名, 封面圖網址, 播放網址]
   */
  Future<List<String>?> getArtistAndTracks(String singer, String song);
  Future<List<Map<String, String>>?> getTop5ArtistAndTracks(String query);
}