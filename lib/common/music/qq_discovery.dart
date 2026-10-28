// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'music_source.dart';
import 'qq_music.dart';

class QqPodcast {
  const QqPodcast(
      {required this.id,
      required this.name,
      this.image = '',
      this.author = ''});
  final String id, name, image, author;
}

class QqPlaylistPage {
  const QqPlaylistPage(this.playlists,
      {required this.nextOffset, required this.hasMore});
  final List<SourcePlaylist> playlists;
  final int nextOffset;
  final bool hasMore;
}

/// QQ discovery uses the same account and playback transport as its library.
class QqDiscovery {
  QqDiscovery(this.qq);
  final QqMusic qq;
  String _dailyAccount = '', _dailyDate = '';
  List<MediaItem> _daily = [];
  bool podcastsHaveMore = false;

  /// Public playlist recommendations, distinct from a user's daily song list.
  Future<QqPlaylistPage> recommendedPlaylists(
      {int offset = 0, CancelToken? cancelToken}) async {
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    await qq.restore();
    final account = qq.account;
    final data = await qq.rpc('music.playlist.PlaylistSquare',
        'GetRecommendFeed', {'From': offset, 'Size': 20},
        expectedAccount: account, cancelToken: cancelToken);
    if (qq.account != account) throw const MusicServiceError('QQ账号已切换，请刷新推荐歌单');
    final raw = data['List'];
    if (raw is! List) throw const MusicServiceError('QQ音乐未返回推荐歌单，请重试');
    final result = <SourcePlaylist>[];
    final ids = <String>{};
    for (final item in raw.whereType<Map>()) {
      final playlist = item['Playlist'];
      final basic = playlist is Map ? playlist['basic'] : null;
      if (basic is! Map) continue;
      final id = '${basic['tid'] ?? ''}';
      if ((BigInt.tryParse(id) ?? BigInt.zero) <= BigInt.zero || !ids.add(id)) {
        continue;
      }
      final cover = basic['cover'];
      var image = '';
      if (cover is Map) {
        for (final field in ['medium_url', 'default_url', 'small_url']) {
          var candidate = '${cover[field] ?? ''}'.trim();
          if (candidate.startsWith('//')) candidate = 'https:$candidate';
          final uri = Uri.tryParse(candidate);
          if (uri != null &&
              uri.host.isNotEmpty &&
              ['http', 'https'].contains(uri.scheme)) {
            image = uri.replace(scheme: 'https').toString();
            break;
          }
        }
      }
      result.add(SourcePlaylist(
          source: MusicSource.qq,
          id: id,
          directory: '${basic['dirid'] ?? ''}',
          name: QqMusic.clean(basic['title']),
          image: image,
          count: (basic['song_cnt'] as num? ?? 0).toInt()));
    }
    if (raw.isNotEmpty && result.isEmpty) {
      throw const MusicServiceError('QQ音乐推荐歌单格式异常，请重试');
    }
    final next = offset + raw.length;
    final limit = (data['FromLimit'] as num?)?.toInt();
    return QqPlaylistPage(result,
        nextOffset: next,
        hasMore: raw.isNotEmpty &&
            data['HasMore'] == true &&
            (limit == null || limit <= 0 || next < limit));
  }

  void _check(String account) {
    if (!qq.loggedIn || qq.account != account) {
      throw const MusicServiceError('QQ音乐账号已切换，请重新加载');
    }
  }

  static List<Map> maps(Object? value) =>
      value is List ? value.whereType<Map>().toList() : const [];
  static List<MediaItem> songs(Object? value) {
    final result = <MediaItem>[];
    final ids = <String>{};
    for (final item in maps(value)) {
      final raw = item['track_info'] is Map
          ? item['track_info'] as Map
          : item['songInfo'] is Map
              ? item['songInfo'] as Map
              : item;
      final parsed = QqMusic.song(raw);
      if (ids.add(parsed.id)) result.add(parsed);
    }
    return result;
  }

  Future<List<MediaItem>> dailySongs(
      {bool refresh = false, CancelToken? cancelToken}) async {
    await qq.restore();
    if (!qq.loggedIn) throw const MusicServiceError('请先登录QQ音乐');
    final account = qq.account;
    final date = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 8))
        .toIso8601String()
        .substring(0, 10);
    if (!refresh &&
        _dailyAccount == account &&
        _dailyDate == date &&
        _daily.isNotEmpty) return List.of(_daily);
    final data = await qq.rpc(
        'music.recommend.RecommendFeed',
        'get_recommend_feed',
        {'page': 1, 'direction': 0, 's_num': 0, 'v_cache': []},
        auth: true,
        expectedAccount: account,
        cancelToken: cancelToken);
    _check(account);
    // Daily recommendation cards are distinct from general playlists and radio.
    final dailyCards = <String, Map>{};
    void visit(Object? value) {
      if (value is Map) {
        if ('${value['subtype']}' == '510') {
          final id = '${value['id'] ?? ''}';
          if ((BigInt.tryParse(id) ?? BigInt.zero) > BigInt.zero)
            dailyCards[id] = value;
        }
        for (final item in value.values) {
          if (item is Map || item is List) visit(item);
        }
      } else if (value is List) {
        for (final item in value) visit(item);
      }
    }

    visit(data);
    if (dailyCards.length != 1)
      throw const MusicServiceError('QQ音乐暂未提供今日推荐，请稍后刷新');
    final misc = dailyCards.values.single['miscellany'];
    final directory = misc is Map ? '${misc['dirid'] ?? ''}' : '';
    final list = SourcePlaylist(
        source: MusicSource.qq,
        id: dailyCards.keys.single,
        directory: directory,
        name: 'QQ音乐每日推荐');
    final tracks = await qq.playlistSongs(list);
    _check(account);
    if (tracks.isEmpty) throw const MusicServiceError('QQ音乐今日推荐暂时为空，请稍后刷新');
    _dailyAccount = account;
    _dailyDate = date;
    _daily = List.of(tracks);
    return tracks;
  }

  Future<List<MediaItem>> radioSongs(
      {Set<String> recentIds = const {}, CancelToken? cancelToken}) async {
    await qq.restore();
    if (!qq.loggedIn) throw const MusicServiceError('请先登录QQ音乐');
    final account = qq.account;
    final data = await qq.rpc(
        'music.radioProxy.MbTrackRadioSvr',
        'get_radio_track',
        {
          'id': 99,
          'num': 15,
          'from': 0,
          'scene': 0,
          // This endpoint accepts an empty history; non-empty numeric arrays
          // are rejected by the service (22006). Filter history locally instead.
          'song_ids': <int>[],
        },
        auth: true,
        expectedAccount: account,
        cancelToken: cancelToken);
    _check(account);
    final tracks = songs(data['tracks']);
    if (tracks.isEmpty) throw const MusicServiceError('QQ音乐暂未提供电台歌曲，请稍后重试');
    return tracks
        .where((track) => !recentIds.contains('${track.extras?['qqId'] ?? ''}'))
        .toList();
  }

  Future<List<QqPodcast>> podcasts(
      {String query = '播客', int page = 1, CancelToken? cancelToken}) async {
    await qq.restore();
    if (!qq.loggedIn) throw const MusicServiceError('请先登录QQ音乐');
    final account = qq.account;
    // The public web search identifies podcast hosts with singer_identity=14.
    // Their native album lists identify actual voice albums, rather than songs
    // whose titles happen to contain the search word.
    final data = await qq.rpc(
        'music.adaptor.SearchAdaptor',
        'do_search_v2',
        {
          'query': query,
          'search_type': 1,
          'num_per_page': 20,
          'page_num': page,
          'searchid': '${DateTime.now().microsecondsSinceEpoch}',
          'highlight': 0,
        },
        auth: true,
        expectedAccount: account,
        cancelToken: cancelToken);
    _check(account);
    final body = data['body'] is Map ? data['body'] as Map : const {};
    final hosts = <String, Map>{};
    void collect(Object? value) {
      if (value is List) {
        for (final item in value) collect(item);
        return;
      }
      if (value is! Map) return;
      final info =
          value['custom_info'] is Map ? value['custom_info'] as Map : const {};
      final identity =
          '${info['singer_identity'] ?? value['singer_identity'] ?? value['singerType'] ?? ''}';
      final mid = '${info['mid'] ?? value['mid'] ?? value['singerMid'] ?? ''}';
      if (identity == '14' && RegExp(r'^[A-Za-z0-9]{14}$').hasMatch(mid))
        hosts[mid] = value;
      for (final child in value.values) {
        if (child is Map || child is List) collect(child);
      }
    }

    collect(body);
    final albums = <String, QqPodcast>{};
    for (final host in hosts.entries.take(8)) {
      final list = await qq.rpc(
          'music.musichallAlbum.AlbumListServer',
          'GetAlbumList',
          {
            'singerMid': host.key,
            'order': 0,
            'number': 30,
            'begin': 0,
          },
          auth: true,
          expectedAccount: account,
          cancelToken: cancelToken);
      _check(account);
      for (final album in maps(list['albumList'])) {
        if ('${album['albumType'] ?? ''}' != '人声音频') continue;
        final mid = '${album['albumMid'] ?? ''}';
        final name = QqMusic.clean(album['albumName']);
        if (mid.isEmpty || name.isEmpty) continue;
        final cover = '${album['pmid'] ?? mid}';
        albums[mid] = QqPodcast(
            id: mid,
            name: name,
            image:
                'https://y.gtimg.cn/music/photo_new/T002R300x300M000$cover.jpg',
            author: QqMusic.clean(album['singerName'] ?? host.value['title']));
      }
    }
    final meta = data['meta'];
    final total = meta is Map ? (meta['sum'] as num? ?? 0).toInt() : 0;
    podcastsHaveMore = total > page * 20 && hosts.isNotEmpty;
    if (albums.isEmpty &&
        meta is Map &&
        meta['is_filter'] is num &&
        meta['is_filter'] < 0) {
      throw const MusicServiceError('QQ音乐播客服务暂未返回结果，请稍后重试');
    }
    return albums.values.toList();
  }

  Future<List<MediaItem>> podcastEpisodes(QqPodcast podcast,
      {int page = 1, CancelToken? cancelToken}) async {
    await qq.restore();
    final account = qq.account;
    final numeric = int.tryParse(podcast.id);
    final data = await qq.rpc(
        'music.musichallAlbum.AlbumSongList',
        'GetAlbumSongList',
        {
          if (numeric != null) 'albumId': numeric else 'albumMid': podcast.id,
          'begin': (page - 1) * 50,
          'num': 50,
        },
        auth: true,
        expectedAccount: account,
        cancelToken: cancelToken);
    _check(account);
    final tracks = songs(data['songList'] ?? data['songlist']);
    return tracks
        .map((track) => track.copyWith(
              artUri: podcast.image.isEmpty
                  ? track.artUri
                  : Uri.tryParse(podcast.image),
              extras: {
                ...?track.extras,
                'qqPodcast': true,
                if (podcast.image.isNotEmpty) 'image': podcast.image
              },
            ))
        .toList();
  }
}
