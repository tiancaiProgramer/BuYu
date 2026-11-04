// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/music/catalog_search.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in CatalogKind.values) {
    test(
        '${kind.name} uses actual desktop envelope, distinct identity, real metadata',
        () async {
      final client = Dio();
      client.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final body = o.data as Map;
        expect(body.containsKey('comm'), false);
        final req = body['music.search.SearchCgiService'] as Map;
        expect(req['param']['search_type'], kind.qqType);
        expect(req['param']['page_num'], 2);
        h.resolve(Response(requestOptions: o, data: {
          'code': 0,
          'music.search.SearchCgiService': {
            'code': 0,
            'data': {
              'body': {
                kind.qqField: {
                  'list': [
                    {
                      'dissid': '55',
                      'dissname': '歌单',
                      'albumMID': 'album',
                      'albumName': '专辑',
                      'singerMID': 'artist',
                      'singerName': '歌手',
                      'imgurl': 'http://y.gtimg.cn/cover',
                      'song_count': 3,
                    }
                  ]
                }
              }
            }
          }
        }));
      }));
      final qq = QqMusic(dio: client);
      final result = await CatalogSearch.qq(qq, kind, '测试', 2);
      expect(result.length, 1);
      expect(sourceOf(result.single), MusicSource.qq);
      expect(result.single.extras!['catalogKind'], kind.name);
      expect(result.single.artUri.toString(), startsWith('https://'));
      expect(result.single.id, startsWith('qq:${kind.name}:'));
      qq.dispose();
    });
  }
  test(
      'album and singer detail load exact IDs, unwrap actual songInfo, keep QQ playback source',
      () async {
    final client = Dio();
    final seen = <Map>[];
    client.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      seen.add(o.data['req_0'] as Map);
      h.resolve(Response(requestOptions: o, data: {
        'code': 0,
        'req_0': {
          'code': 0,
          'data': {
            'songList': [
              {
                'songInfo': {'mid': 'song', 'id': 123, 'title': '曲目'}
              }
            ]
          }
        }
      }));
    }));
    final qq = QqMusic(dio: client);
    for (final kind in [CatalogKind.album, CatalogKind.artist]) {
      final item = MediaItem(
          id: 'qq:entity',
          title: '目录',
          extras: {'catalogKind': kind.name, 'catalogId': 'exact-mid'});
      final songs = await CatalogSearch.qqSongs(qq, item, 2);
      expect(songs.single.id, 'qq:song');
      expect(songs.single.extras!['qqId'], '123');
      expect(
          seen.last['param']
              [kind == CatalogKind.album ? 'albumMid' : 'singerMid'],
          'exact-mid');
      expect(seen.last['param']['begin'], 100);
    }
    qq.dispose();
  });
  test(
      'missing result bucket is a retryable error rather than false empty result',
      () async {
    final client = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.resolve(Response(requestOptions: o, data: {
                'code': 0,
                'music.search.SearchCgiService': {
                  'code': 0,
                  'data': {'body': {}}
                }
              }))));
    final qq = QqMusic(dio: client);
    await expectLater(CatalogSearch.qq(qq, CatalogKind.album, 'x', 1),
        throwsA(isA<MusicServiceError>()));
    qq.dispose();
  });
}
