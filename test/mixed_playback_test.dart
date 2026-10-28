// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:bujuan/common/netease_api/src/netease_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'playback_regression_test.dart' show FakePlayer, TestApiPaths;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'mixed queue resolves each platform separately and preserves its metadata',
      () async {
    final dir = await Directory.systemTemp.createTemp('buyu-mixed-playback-');
    Hive.init(dir.path);
    final box = await Hive.openBox('mixed-playback');
    await NeteaseMusicApi.init(provider: TestApiPaths(dir.path));
    final previous = Https.dio.interceptors.toList();
    final requests = <String>[];
    Https.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
      expect((o.data as Map)['ids'], isNot(contains('qq:')));
      requests.add('netease');
      h.resolve(Response(requestOptions: o, data: {
        'code': 200,
        'data': [
          {
            'id': '123',
            'url': 'https://example.test/netease.mp3?token=retained',
            'level': 'exhigh'
          }
        ]
      }));
    }));
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final req = (o.data as Map)['req_0'] as Map;
      expect(req['method'], 'CgiGetVkey');
      expect(req['param']['songmid'], ['abc']);
      requests.add('qq');
      h.resolve(Response(requestOptions: o, data: {
        'code': 0,
        'req_0': {
          'code': 0,
          'data': {
            'sip': ['https://dl.stream.qqmusic.qq.com/'],
            'midurlinfo': [
              {'purl': 'M800media.mp3?vkey=retained'}
            ]
          }
        }
      }));
    }));
    final qq = QqMusic(dio: dio);
    GetIt.I.registerSingleton<QqMusic>(qq);
    final player = FakePlayer();
    final handler =
        BujuanAudioHandler(player: player, box: box, restoreQueue: false);
    try {
      await handler.changeQueueLists([
        const MediaItem(id: '123', title: '网易版本', artist: '网易歌手'),
        const MediaItem(
            id: 'qq:abc',
            title: 'QQ版本',
            artist: 'QQ歌手',
            extras: {'source': 'qq', 'mid': 'abc', 'mediaMid': 'media'})
      ]);
      expect(handler.mediaItem.value?.title, '网易版本');
      await handler.skipToNext();
      expect(handler.mediaItem.value?.id, 'qq:abc');
      expect(handler.mediaItem.value?.artist, 'QQ歌手');
      expect(player.loadedUrls.last,
          'https://dl.stream.qqmusic.qq.com/M800media.mp3?vkey=retained');
      expect(handler.qualityReport.value?.returnedLevel, 'exhigh');
      await handler.skipToPrevious();
      expect(handler.mediaItem.value?.id, '123');
      expect(requests, ['netease', 'qq', 'netease']);
      expect(handler.queue.value.map((s) => s.id), ['123', 'qq:abc']);
    } finally {
      await handler.dispose();
      Https.dio.interceptors
        ..clear()
        ..addAll(previous);
      qq.dispose();
      await GetIt.I.reset();
      await box.close();
      await dir.delete(recursive: true);
    }
  });
}
