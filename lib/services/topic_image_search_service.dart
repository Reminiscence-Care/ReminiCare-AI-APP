import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/reminiscence_topic.dart';
import 'ai/cloud_vision_reranker.dart';

class TopicThumbnailResult {
  const TopicThumbnailResult({
    required this.path,
    required this.sourceId,
    required this.width,
    required this.height,
    required this.attribution,
  });

  final String path;
  final String sourceId;
  final int width;
  final int height;
  final TopicImageAttribution attribution;

  Map<String, dynamic> toJson() => {
    'path': path,
    'sourceId': sourceId,
    'width': width,
    'height': height,
    'attribution': attribution.toJson(),
  };

  factory TopicThumbnailResult.fromJson(Map<String, dynamic> json) =>
      TopicThumbnailResult(
        path: (json['path'] ?? '').toString(),
        sourceId: (json['sourceId'] ?? '').toString(),
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        attribution: TopicImageAttribution.fromJson(
          Map<String, dynamic>.from(
            json['attribution'] as Map? ?? const <String, dynamic>{},
          ),
        ),
      );
}

abstract interface class ITopicImageSearchClient {
  Future<TopicThumbnailResult> findForTopic(
    ReminiscenceTopic topic, {
    Set<String> excludedSourceIds = const {},
  });
}

abstract interface class ITopicImageCache {
  Future<TopicThumbnailResult?> find(
    String query, {
    Set<String> excludedSourceIds = const {},
  });

  Future<TopicThumbnailResult> store({
    required String query,
    required Uint8List bytes,
    required String extension,
    required String sourceId,
    required int width,
    required int height,
    required TopicImageAttribution attribution,
  });
}

class TopicImageSearchException implements Exception {
  const TopicImageSearchException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TopicImageSearchClient implements ITopicImageSearchClient {
  TopicImageSearchClient({
    http.Client? httpClient,
    ITopicImageCache? cache,
    ITopicImageReranker? reranker,
    this.timeout = const Duration(seconds: 10),
  }) : _http = httpClient ?? http.Client(),
       _cache = cache ?? DefaultTopicImageCache(),
       _reranker = reranker;

  static const _allowedLicenses = {'cc0', 'pdm', 'by', 'by-sa'};
  static const _maxDownloadBytes = 8 * 1024 * 1024;

  final http.Client _http;
  final ITopicImageCache _cache;
  final ITopicImageReranker? _reranker;
  final Duration timeout;

  @override
  Future<TopicThumbnailResult> findForTopic(
    ReminiscenceTopic topic, {
    Set<String> excludedSourceIds = const {},
  }) async {
    final query = topic.imageSearchQuery.trim();
    final cacheQuery = 'topic-image-v2|$query';
    TopicThumbnailResult? cached;
    try {
      cached = await _cache.find(
        cacheQuery,
        excludedSourceIds: excludedSourceIds,
      );
    } catch (_) {
      // A damaged or unavailable cache must not prevent a network search.
    }
    if (cached != null) return cached;

    final candidates = <String, _TopicImageCandidate>{};
    for (final part in _queryParts(topic)) {
      late http.Response response;
      try {
        response = await _http
            .get(
              Uri.https('api.openverse.org', '/v1/images/', {
                'q': part,
                'license': 'cc0,pdm,by,by-sa',
                'mature': 'false',
                'page_size': '20',
              }),
              headers: const {
                'Accept': 'application/json',
                'User-Agent': 'ReminiCare/1.0 (topic image search)',
              },
            )
            .timeout(timeout);
      } catch (_) {
        // Chinese and English query variants are independent fallbacks.
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        continue;
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        continue;
      }
      final results = decoded is Map<String, dynamic>
          ? decoded['results']
          : null;
      if (results is! List) continue;
      for (final value in results.whereType<Map<String, dynamic>>()) {
        final candidate = _TopicImageCandidate.fromJson(value);
        if (candidate == null ||
            excludedSourceIds.contains(candidate.id) ||
            candidates.containsKey(candidate.id)) {
          continue;
        }
        candidates[candidate.id] = candidate;
      }
    }

    var ranked = candidates.values.toList()
      ..sort((a, b) => b.scoreFor(query).compareTo(a.scoreFor(query)));
    final reranker = _reranker;
    if (reranker != null && ranked.isNotEmpty) {
      final shortlist = ranked.take(8).toList();
      final rankedIds = await reranker.rank(
        topic: topic,
        candidates: shortlist
            .map(
              (candidate) => TopicVisionCandidate(
                sourceId: candidate.id,
                imageUrl: candidate.imageUrls.first,
                title: candidate.attribution.title,
              ),
            )
            .toList(),
      );
      if (rankedIds.isEmpty) {
        throw const TopicImageSearchException('雲端圖片判斷沒有找到符合主題的照片。');
      }
      final byId = {for (final candidate in shortlist) candidate.id: candidate};
      ranked = rankedIds
          .map((id) => byId[id])
          .whereType<_TopicImageCandidate>()
          .toList();
    }
    for (final candidate in ranked.take(12)) {
      try {
        return await _downloadAndStore(candidate, cacheQuery);
      } catch (_) {
        // A broken or undersized result should not prevent trying the next
        // openly licensed candidate.
      }
    }
    throw const TopicImageSearchException('找不到適合且可公開使用的主題圖片。');
  }

  Future<TopicThumbnailResult> _downloadAndStore(
    _TopicImageCandidate candidate,
    String query,
  ) async {
    Object? lastError;
    for (final imageUrl in candidate.imageUrls) {
      try {
        final uri = Uri.tryParse(imageUrl);
        if (uri == null || uri.scheme != 'https') {
          throw const TopicImageSearchException('圖片網址不是 HTTPS。');
        }
        final response = await _http.get(uri).timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw TopicImageSearchException('圖片下載失敗：HTTP ${response.statusCode}');
        }
        final contentType = response.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase();
        if (contentType == null || !contentType.startsWith('image/')) {
          throw const TopicImageSearchException('下載內容不是圖片。');
        }
        final declaredLength = int.tryParse(
          response.headers['content-length'] ?? '',
        );
        if ((declaredLength != null && declaredLength > _maxDownloadBytes) ||
            response.bodyBytes.length > _maxDownloadBytes) {
          throw const TopicImageSearchException('圖片檔案過大。');
        }
        final size = await _decodeSize(response.bodyBytes);
        if (size.$1 < 320 || size.$2 < 240 || size.$1 * size.$2 < 180000) {
          throw const TopicImageSearchException('圖片解析度不足。');
        }
        return _cache.store(
          query: query,
          bytes: response.bodyBytes,
          extension: _extensionFor(contentType),
          sourceId: candidate.id,
          width: size.$1,
          height: size.$2,
          attribution: candidate.attribution,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw TopicImageSearchException('圖片候選下載失敗：${lastError ?? '沒有可用網址'}');
  }

  static Future<(int, int)> _decodeSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final result = (frame.image.width, frame.image.height);
      frame.image.dispose();
      return result;
    } finally {
      codec.dispose();
    }
  }

  static List<String> _queryParts(ReminiscenceTopic topic) {
    const canonicalQueries = <String, String>{
      'childhood_games': 'Taiwan children playing traditional games',
      'school_life': 'Taiwan students classroom school historical',
      'traditional_food': 'Taiwan traditional food street vendor',
      'market': 'Taiwan traditional market vendors',
      'farming': 'Taiwan farmers rice harvest historical',
      'railway': 'Taiwan railway station train historical',
      'festivals': 'Taiwan traditional festival celebration historical',
      'family': 'Taiwan family daily life historical photograph',
      'work': 'Taiwan workers traditional occupation historical',
      'neighborhood': 'Taiwan old street neighborhood historical',
      'entertainment': 'Taiwan traditional performance leisure historical',
    };
    final parts = <String>{
      ?canonicalQueries[topic.categoryId],
      ...topic.imageSearchQuery
          .split('|')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty),
    }.take(3).toList();
    return parts.isEmpty ? [topic.title] : parts;
  }

  static String _extensionFor(String contentType) => switch (contentType) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'jpg',
  };
}

class WikimediaTopicImageSearchClient implements ITopicImageSearchClient {
  WikimediaTopicImageSearchClient({
    http.Client? httpClient,
    ITopicImageCache? cache,
    this.timeout = const Duration(seconds: 8),
  }) : _http = httpClient ?? http.Client(),
       _cache = cache ?? DefaultTopicImageCache();

  static const _sources = <String, _WikimediaSource>{
    'childhood_games': _WikimediaSource.category(
      'Category:Children playing in Taiwan',
    ),
    'school_life': _WikimediaSource.category(
      'Category:Historical images of schools in Taiwan',
    ),
    'traditional_food': _WikimediaSource.category('Category:Candy of Taiwan'),
    'market': _WikimediaSource.category('Category:Night markets in Taiwan'),
    'farming': _WikimediaSource.category(
      'Category:Historical images of agriculture in Taiwan',
    ),
    // This Commons category currently has no reusable direct files. A tested
    // MediaSearch query reliably returns historical Taiwan station photos.
    'railway': _WikimediaSource.search('Taiwan railway station historical'),
    'festivals': _WikimediaSource.category('Category:Festivals in Taiwan'),
    'family': _WikimediaSource.category('Category:Families of Taiwan'),
    'work': _WikimediaSource.category('Category:People at work in Taiwan'),
    'neighborhood': _WikimediaSource.category('Category:Old streets in Taiwan'),
    'entertainment': _WikimediaSource.category('Category:Taiwanese opera'),
  };

  final http.Client _http;
  final ITopicImageCache _cache;
  final Duration timeout;

  @override
  Future<TopicThumbnailResult> findForTopic(
    ReminiscenceTopic topic, {
    Set<String> excludedSourceIds = const {},
  }) async {
    final source = _sources[topic.categoryId];
    if (source == null) {
      throw const TopicImageSearchException('這個主題沒有對應的圖片分類。');
    }
    // The controlled category/search, rather than model wording, identifies
    // the cache entry. Re-recommendations can therefore reuse the same file
    // without another public API request.
    final cacheQuery = 'commons-v2|${source.cacheKey}';
    try {
      final cached = await _cache.find(
        cacheQuery,
        excludedSourceIds: excludedSourceIds,
      );
      if (cached != null) return cached;
    } catch (_) {
      // Continue with the network when cache metadata is unavailable.
    }

    final response = await _http
        .get(
          Uri.https('commons.wikimedia.org', '/w/api.php', {
            'action': 'query',
            'format': 'json',
            'formatversion': '2',
            ...source.queryParameters,
            'prop': 'info|imageinfo',
            'inprop': 'url',
            'iiprop': 'url|size|mime|extmetadata',
            // 720 px is comfortably above the rendered iPad card width and
            // avoids paying the latency/memory cost of full-size originals.
            'iiurlwidth': '720',
          }),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'ReminiCare/1.0 (topic image selection)',
          },
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TopicImageSearchException(
        'Wikimedia 搜尋失敗：HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final query = decoded is Map<String, dynamic> ? decoded['query'] : null;
    final pages = query is Map ? query['pages'] : null;
    if (pages is! List) {
      throw const TopicImageSearchException('Wikimedia 分類沒有可用照片。');
    }
    final candidates =
        pages
            .whereType<Map<String, dynamic>>()
            .map(_WikimediaCandidate.fromJson)
            .whereType<_WikimediaCandidate>()
            .where((candidate) => !excludedSourceIds.contains(candidate.id))
            .toList()
          ..sort(
            (a, b) => b
                .scoreFor(topic.imageSearchQuery)
                .compareTo(a.scoreFor(topic.imageSearchQuery)),
          );

    // Exact categories are already curated. Bounding retries keeps a broken
    // category or slow connection from stalling the topic picker.
    for (final candidate in candidates.take(3)) {
      try {
        final imageResponse = await _http
            .get(Uri.parse(candidate.imageUrl))
            .timeout(timeout);
        final contentType = imageResponse.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase();
        if (imageResponse.statusCode < 200 ||
            imageResponse.statusCode >= 300 ||
            contentType == null ||
            !contentType.startsWith('image/') ||
            imageResponse.bodyBytes.length >
                TopicImageSearchClient._maxDownloadBytes) {
          continue;
        }
        final size = await TopicImageSearchClient._decodeSize(
          imageResponse.bodyBytes,
        );
        if (size.$1 < 320 || size.$2 < 240 || size.$1 * size.$2 < 180000) {
          continue;
        }
        return _cache.store(
          query: cacheQuery,
          bytes: imageResponse.bodyBytes,
          extension: TopicImageSearchClient._extensionFor(contentType),
          sourceId: candidate.id,
          width: size.$1,
          height: size.$2,
          attribution: candidate.attribution,
        );
      } catch (_) {
        // Try the next file in this already-vetted Commons category.
      }
    }
    throw const TopicImageSearchException('Wikimedia 分類中沒有可下載的合適照片。');
  }
}

class _WikimediaSource {
  const _WikimediaSource.category(this.value) : isSearch = false;
  const _WikimediaSource.search(this.value) : isSearch = true;

  final String value;
  final bool isSearch;

  String get cacheKey => '${isSearch ? 'search' : 'category'}|$value';

  Map<String, String> get queryParameters => isSearch
      ? {
          'generator': 'search',
          'gsrsearch': value,
          'gsrnamespace': '6',
          'gsrlimit': '20',
        }
      : {
          'generator': 'categorymembers',
          'gcmtitle': value,
          'gcmnamespace': '6',
          'gcmlimit': '20',
        };
}

class DefaultTopicImageCache implements ITopicImageCache {
  DefaultTopicImageCache({
    Future<Directory> Function()? directoryProvider,
    this.maxBytes = 100 * 1024 * 1024,
  }) : _directoryProvider =
           directoryProvider ??
           (() async => Directory(
             '${(await getApplicationCacheDirectory()).path}'
             '${Platform.pathSeparator}topic_images',
           ));

  final Future<Directory> Function() _directoryProvider;
  final int maxBytes;

  @override
  Future<TopicThumbnailResult?> find(
    String query, {
    Set<String> excludedSourceIds = const {},
  }) async {
    final directory = await _readyDirectory();
    final metadataFile = File(
      '${directory.path}${Platform.pathSeparator}${_hash(query)}.json',
    );
    if (!await metadataFile.exists()) return null;
    try {
      final decoded = jsonDecode(await metadataFile.readAsString());
      final result = TopicThumbnailResult.fromJson(
        Map<String, dynamic>.from(decoded as Map),
      );
      final image = File(result.path);
      if (excludedSourceIds.contains(result.sourceId) ||
          !await image.exists()) {
        return null;
      }
      await image.setLastModified(DateTime.now());
      await metadataFile.setLastModified(DateTime.now());
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TopicThumbnailResult> store({
    required String query,
    required Uint8List bytes,
    required String extension,
    required String sourceId,
    required int width,
    required int height,
    required TopicImageAttribution attribution,
  }) async {
    final directory = await _readyDirectory();
    final key = _hash(query);
    final image = File(
      '${directory.path}${Platform.pathSeparator}$key.$extension',
    );
    await image.writeAsBytes(bytes, flush: true);
    final result = TopicThumbnailResult(
      path: image.path,
      sourceId: sourceId,
      width: width,
      height: height,
      attribution: attribution,
    );
    final metadata = File(
      '${directory.path}${Platform.pathSeparator}$key.json',
    );
    await metadata.writeAsString(jsonEncode(result.toJson()), flush: true);
    await _trim(directory);
    return result;
  }

  Future<Directory> _readyDirectory() async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<void> _trim(Directory directory) async {
    final images = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File && !entity.path.endsWith('.json')) images.add(entity);
    }
    var total = 0;
    final entries = <(File, FileStat)>[];
    for (final image in images) {
      final stat = await image.stat();
      total += stat.size;
      entries.add((image, stat));
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final entry in entries) {
      if (total <= maxBytes) break;
      final image = entry.$1;
      total -= entry.$2.size;
      await image.delete();
      final name = image.path.split(Platform.pathSeparator).last;
      final stem = name.contains('.')
          ? name.substring(0, name.lastIndexOf('.'))
          : name;
      final metadata = File(
        '${directory.path}${Platform.pathSeparator}$stem.json',
      );
      if (await metadata.exists()) await metadata.delete();
    }
  }

  static String _hash(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value.trim().toLowerCase())) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

class _TopicImageCandidate {
  const _TopicImageCandidate({
    required this.id,
    required this.imageUrls,
    required this.width,
    required this.height,
    required this.searchableText,
    required this.source,
    required this.attribution,
  });

  final String id;
  final List<String> imageUrls;
  final int width;
  final int height;
  final String searchableText;
  final String source;
  final TopicImageAttribution attribution;

  static _TopicImageCandidate? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final license = (json['license'] ?? '').toString().toLowerCase().trim();
    final mature = json['mature'] == true;
    final imageUrls =
        <String>{
          (json['thumbnail'] ?? '').toString().trim(),
          (json['url'] ?? '').toString().trim(),
        }.where((url) {
          final uri = Uri.tryParse(url);
          return uri != null && uri.scheme == 'https';
        }).toList();
    if (id.isEmpty ||
        mature ||
        !TopicImageSearchClient._allowedLicenses.contains(license) ||
        imageUrls.isEmpty) {
      return null;
    }
    final tags = (json['tags'] as List? ?? const [])
        .map((tag) => tag is Map ? tag['name'] : tag)
        .whereType<Object>()
        .join(' ');
    final title = (json['title'] ?? '').toString().trim();
    final creator = (json['creator'] ?? '').toString().trim();
    final source = (json['source'] ?? '').toString().trim();
    final category = (json['category'] ?? '').toString().toLowerCase().trim();
    if (!const {'wikimedia', 'flickr'}.contains(source.toLowerCase()) ||
        (category.isNotEmpty && category != 'photograph')) {
      return null;
    }
    final landing = (json['foreign_landing_url'] ?? '').toString().trim();
    final licenseUrl = (json['license_url'] ?? '').toString().trim();
    return _TopicImageCandidate(
      id: '$source:$id',
      imageUrls: imageUrls,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      searchableText: '$title $tags $creator $source'.toLowerCase(),
      source: source.toLowerCase(),
      attribution: TopicImageAttribution(
        title: title.isEmpty ? '未命名照片' : title,
        creator: creator.isEmpty ? '未知作者' : creator,
        source: source.isEmpty ? 'Openverse' : source,
        license: license.toUpperCase(),
        originalUrl: landing,
        licenseUrl: licenseUrl,
      ),
    );
  }

  double scoreFor(String query) {
    var score = switch (source) {
      'wikimedia' => 8.0,
      'flickr' => 5.0,
      _ => 0.0,
    };
    final tokens = query
        .toLowerCase()
        .replaceAll('|', ' ')
        .split(RegExp(r'[\s,，。.;；:：/\\()\[\]{}|_\-]+'))
        .where((token) => token.length > 1)
        .toSet();
    for (final token in tokens) {
      if (searchableText.contains(token)) score += 4;
    }
    if (searchableText.contains('taiwan') || searchableText.contains('台灣')) {
      score += 6;
    }
    if (width > 0 && height > 0) {
      final ratio = width / height;
      score += 4 - ((ratio - 1).abs().clamp(0, 2) * 2);
      if (width >= 720 || height >= 720) score += 2;
    }
    if (RegExp(
      r'logo|icon|map|diagram|illustration',
    ).hasMatch(searchableText)) {
      score -= 10;
    }
    return score;
  }
}

class _WikimediaCandidate {
  const _WikimediaCandidate({
    required this.id,
    required this.imageUrl,
    required this.searchableText,
    required this.attribution,
  });

  final String id;
  final String imageUrl;
  final String searchableText;
  final TopicImageAttribution attribution;

  static _WikimediaCandidate? fromJson(Map<String, dynamic> page) {
    final pageId = (page['pageid'] as num?)?.toInt();
    final infoList = page['imageinfo'];
    if (pageId == null || infoList is! List || infoList.isEmpty) return null;
    final info = infoList.first;
    if (info is! Map<String, dynamic>) return null;
    final mime = (info['mime'] ?? '').toString().toLowerCase();
    final imageUrl = (info['thumburl'] ?? info['url'] ?? '').toString();
    final uri = Uri.tryParse(imageUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !const {'image/jpeg', 'image/png', 'image/webp'}.contains(mime)) {
      return null;
    }
    final metadata = Map<String, dynamic>.from(
      info['extmetadata'] as Map? ?? const <String, dynamic>{},
    );
    String meta(String key) {
      final value = metadata[key];
      return value is Map ? (value['value'] ?? '').toString().trim() : '';
    }

    final license = meta('LicenseShortName');
    final normalizedLicense = license.toLowerCase().trim();
    final allowed =
        normalizedLicense == 'public domain' ||
        normalizedLicense == 'cc0' ||
        RegExp(r'^cc by(?:-sa)?(?: [0-9.]+)?$').hasMatch(normalizedLicense);
    if (!allowed) return null;

    final rawTitle = (page['title'] ?? '').toString();
    final title = rawTitle.replaceFirst(RegExp(r'^File:'), '');
    final description = _plainText(meta('ImageDescription'));
    final creator = _plainText(meta('Artist'));
    final originalUrl = (page['canonicalurl'] ?? '').toString();
    return _WikimediaCandidate(
      id: 'wikimedia:$pageId',
      imageUrl: imageUrl,
      searchableText: '$title $description'.toLowerCase(),
      attribution: TopicImageAttribution(
        title: title,
        creator: creator.isEmpty ? '未知作者' : creator,
        source: 'Wikimedia Commons',
        license: license,
        originalUrl: originalUrl,
        licenseUrl: meta('LicenseUrl'),
      ),
    );
  }

  double scoreFor(String query) {
    var score = 0.0;
    for (final token
        in query
            .toLowerCase()
            .replaceAll('|', ' ')
            .split(RegExp(r'[\s,，。.;；:：/\\()\[\]{}|_\-]+'))
            .where((token) => token.length > 2)) {
      if (searchableText.contains(token)) score += 3;
    }
    if (searchableText.contains('taiwan') || searchableText.contains('台灣')) {
      score += 2;
    }
    if (RegExp(
      r'\b(18\d{2}|19[0-7]\d)\b|historical|historic|postcard|formosa|日治|老照片',
    ).hasMatch(searchableText)) {
      score += 6;
    }
    if (RegExp(r'\b(20[0-2]\d)\b').hasMatch(searchableText)) {
      score -= 3;
    }
    if (RegExp(
      r'\bmap\b|botanical|cartograph|diagram|illustration|book cover|地圖|圖表|封面',
    ).hasMatch(searchableText)) {
      score -= 20;
    }
    return score;
  }

  static String _plainText(String value) => value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
