// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import '../netease_api/src/dio_ext.dart';
import '../netease_api/src/netease_handler.dart';
import 'music_source.dart';
import 'qq_music.dart';

enum CatalogKind {
  playlist('歌单', 1000, 3, 'playlists', 'songlist'),
  album('专辑', 10, 2, 'albums', 'album'),
  artist('歌手', 100, 1, 'artists', 'singer');

  const CatalogKind(
      this.label, this.neType, this.qqType, this.neField, this.qqField);
  final String label, neField, qqField;
  final int neType, qqType;
}

class CatalogSearch {
  static MediaItem neteaseItem(CatalogKind kind, Map raw) => MediaItem(
          id: 'netease:${kind.name}:${raw['id']}',
          title: '${raw['name'] ?? ''}',
          artist:
              '${raw['artist'] is Map ? raw['artist']['name'] ?? '' : raw['creator'] is Map ? raw['creator']['nickname'] ?? '' : ''}',
          artUri: Uri.tryParse('${raw['coverImgUrl'] ?? raw['picUrl'] ?? ''}'),
          extras: {
            'source': 'netease',
            'catalogRaw': Map<String, dynamic>.from(raw),
            'catalogKind': kind.name
          });

  static Future<List<MediaItem>> netease(
      CatalogKind kind, String query, int page) async {
    final response = await Https.dioProxy.postUri(DioMetaData(
        joinUri('/weapi/cloudsearch/pc'),
        data: {
          's': query,
          'type': kind.neType,
          'limit': 20,
          'offset': (page - 1) * 20
        },
        options: joinOptions()));
    final raw = response.data;
    if (raw is! Map || raw['code'] != 200 || raw['result'] is! Map) {
      throw const MusicServiceError('网易云分类搜索失败，请重试');
    }
    return (raw['result'][kind.neField] as List? ?? [])
        .whereType<Map>()
        .map((m) => neteaseItem(kind, m))
        .toList();
  }

  static MediaItem qqItem(CatalogKind kind, Map raw) {
    final id = '${switch (kind) {
          CatalogKind.playlist => raw['dissid'] ?? raw['tid'],
          CatalogKind.album => raw['albumMID'] ?? raw['albumMid'] ?? raw['mid'],
          CatalogKind.artist =>
            raw['singerMID'] ?? raw['singerMid'] ?? raw['mid'],
        } ?? ''}';
    if (id.isEmpty) throw const FormatException('QQ catalog item without ID');
    return MediaItem(
        id: 'qq:${kind.name}:$id',
        title: QqMusic.clean(raw['dissname'] ??
            raw['albumName'] ??
            raw['singerName'] ??
            raw['name']),
        artist: QqMusic.clean(kind == CatalogKind.playlist
            ? ((raw['creator'] as Map?)?['name'] ?? '')
            : kind == CatalogKind.album
                ? (raw['singerName'] ?? '')
                : ''),
        artUri: Uri.tryParse(
            '${raw['imgurl'] ?? raw['albumPic'] ?? raw['singerPic'] ?? ''}'
                .replaceFirst('http://', 'https://')),
        extras: {
          'source': 'qq',
          'catalogKind': kind.name,
          'catalogId': id,
          'count': raw['song_count'] ?? raw['songNum'] ?? 0
        });
  }

  static Future<List<MediaItem>> qq(
      QqMusic api, CatalogKind kind, String query, int page) async {
    final data = await api
        .rpc('music.search.SearchCgiService', 'DoSearchForQQMusicDesktop', {
      'query': query,
      'search_type': kind.qqType,
      'num_per_page': 20,
      'page_num': page,
      'highlight': 0,
    });
    final bucket = (data['body'] as Map?)?[kind.qqField];
    if (bucket is! Map || bucket['list'] is! List) {
      throw const MusicServiceError('QQ分类搜索未返回完整结果，请重试');
    }
    return (bucket['list'] as List)
        .whereType<Map>()
        .map((m) => qqItem(kind, m))
        .toList();
  }

  static Future<List<MediaItem>> qqSongs(
      QqMusic api, MediaItem item, int page) async {
    final kind =
        CatalogKind.values.byName(item.extras!['catalogKind'] as String);
    final id = item.extras!['catalogId'] as String;
    if (kind == CatalogKind.playlist) {
      return api.playlistSongs(
          SourcePlaylist(source: MusicSource.qq, id: id, name: item.title),
          page: page);
    }
    final album = kind == CatalogKind.album;
    final data = await api.rpc(
        album
            ? 'music.musichallAlbum.AlbumSongList'
            : 'musichall.song_list_server',
        album ? 'GetAlbumSongList' : 'GetSingerSongList',
        album
            ? {
                'albumMid': id,
                'begin': (page - 1) * 100,
                'num': 100,
                'order': 2
              }
            : {
                'singerMid': id,
                'begin': (page - 1) * 100,
                'number': 100,
                'order': 1
              });
    final raw = data[album ? 'songList' : 'songList'];
    if (raw is! List) throw const MusicServiceError('QQ歌曲目录暂不可用，请重试');
    return raw
        .whereType<Map>()
        .map((m) =>
            QqMusic.song(m['songInfo'] is Map ? m['songInfo'] as Map : m))
        .toList();
  }
}
