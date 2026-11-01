// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/audio_quality_preferences.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:bujuan/common/netease_api/src/netease_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'playback_regression_test.dart' show FakePlayer, TestApiPaths;

Future<void> settled(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final source in MusicSource.values) {
    group('${source.name} playback quality switch', () {
      late Directory dir;
      late MemoryBox box;
      late FakePlayer player;
      late BujuanAudioHandler handler;
      late QqMusic qq;
      late Dio dio;
      late List<Interceptor> previous;
      late List<String> requests;
      late String mode;
      final song = source == MusicSource.qq
          ? const MediaItem(
              id: 'qq:abc',
              title: 'QQ',
              extras: {'source': 'qq', 'mid': 'abc', 'mediaMid': 'media'})
          : const MediaItem(id: '123', title: 'NetEase');
      setUp(() async {
        dir = await Directory.systemTemp.createTemp('buyu-quality-switch-');
        await NeteaseMusicApi.init(provider: TestApiPaths(dir.path));
        box = MemoryBox();
        await box.put(audioQualitySp, 'lossless');
        mode = 'normal';
        requests = [];
        player = FakePlayer();
        dio = Dio();
        previous = Https.dio.interceptors.toList();
        Https.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (o, h) {
          final data = o.data as Map;
          if (data['level'] == null) {
            h.resolve(Response(requestOptions: o, data: {
              'code': 200,
              'songs': [
                {
                  'id': 123,
                  'sq': {'size': 999}
                }
              ]
            }));
            return;
          }
          final quality = data['level'] as String;
          requests.add(quality);
          if (quality == 'lossless' && mode == 'api-error') {
            h.reject(DioException(
                requestOptions: o, type: DioExceptionType.connectionError));
            return;
          }
          h.resolve(Response(requestOptions: o, data: {
            'code': 200,
            'data': [
              {
                'id': '123',
                'url': 'https://example.test/$quality.flac',
                'level': quality == 'lossless' && mode == 'server-lower'
                    ? 'standard'
                    : quality,
                'size': 100
              }
            ]
          }));
        }));
        dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          final filename =
              (o.data as Map)['req_0']['param']['filename'][0] as String;
          final quality = filename.startsWith('F000')
              ? 'lossless'
              : filename.startsWith('M800')
                  ? 'exhigh'
                  : 'standard';
          requests.add(quality);
          if (quality == 'lossless' && mode == 'api-error') {
            h.reject(DioException(
                requestOptions: o, type: DioExceptionType.connectionError));
            return;
          }
          h.resolve(Response(requestOptions: o, data: {
            'code': 0,
            'req_0': {
              'code': 0,
              'data': {
                'sip': ['https://dl.stream.qqmusic.qq.com/'],
                'midurlinfo': [
                  {
                    'purl': quality == 'lossless' && mode == 'server-lower'
                        ? 'M500media.mp3'
                        : filename
                  }
                ]
              }
            }
          }));
        }));
        qq = QqMusic(dio: dio);
        GetIt.I.registerSingleton<QqMusic>(qq);
        handler =
            BujuanAudioHandler(player: player, box: box, restoreQueue: false);
      });
      tearDown(() async {
        await handler.dispose();
        qq.dispose();
        await GetIt.I.reset();
        Https.dio.interceptors
          ..clear()
          ..addAll(previous);
        await dir.delete(recursive: true);
      });
      test('defaults on and recovers an unavailable URL at a lower tier',
          () async {
        mode = 'api-error';
        await handler.changeQueueLists([song]);
        expect(requests, ['lossless', 'exhigh']);
        expect(player.playing, isTrue);
        expect(handler.qualityReport.value?.returnedLevel, 'exhigh');
      });
      test('defaults on and lowers quality after native source failure',
          () async {
        player.loadCallback = (value) async {
          final path = (value as UriAudioSource).uri.path;
          if (path.contains('lossless') || path.contains('F000'))
            throw StateError('CDN unavailable');
          return const Duration(minutes: 3);
        };
        await handler.changeQueueLists([song]);
        expect(requests, ['lossless', 'exhigh']);
        expect(player.playing, isTrue);
      });
      test(
          'enabled runtime recovery lowers quality on the same song and keeps position',
          () async {
        await handler.changeQueueLists([song]);
        await player.seek(const Duration(seconds: 42));
        player.events.addError(StateError('Stream failed'));
        await settled(() => requests.length == 2 && player.playing);
        expect(requests, ['lossless', 'exhigh']);
        expect(handler.mediaItem.value?.id, song.id);
        expect(player.position, const Duration(seconds: 42));
      });
      for (final failure in ['api-error', 'native-error', 'server-lower']) {
        test(
            'disabled $failure never requests lower tiers or skips the selected song',
            () async {
          await handler.setPlaybackFallback(false);
          mode = failure;
          if (failure == 'native-error')
            player.loadCallback = (_) async => throw StateError('CDN failed');
          await handler.changeQueueLists([
            song,
            song.copyWith(id: source == MusicSource.qq ? 'qq:next' : '456')
          ]);
          expect(requests, isNotEmpty);
          expect(requests.every((q) => q == 'lossless'), isTrue);
          expect(requests.length, lessThanOrEqualTo(2));
          expect(handler.playbackState.value.processingState,
              AudioProcessingState.error);
          expect(handler.mediaItem.value?.id, song.id);
          expect(player.playing, isFalse);
          if (failure == 'server-lower') expect(player.loadedUrls, isEmpty);
        });
      }
      test('disabled asynchronous errors retry the same tier then stop',
          () async {
        await handler.setPlaybackFallback(false);
        await handler.changeQueueLists([song]);
        player.events.addError(StateError('Stream failed'));
        await settled(() => requests.length == 2 && player.playing);
        player.events.addError(StateError('Stream failed again'));
        await settled(() =>
            handler.playbackState.value.processingState ==
            AudioProcessingState.error);
        expect(requests, ['lossless', 'lossless']);
        expect(player.playing, isFalse);
      });
      if (source == MusicSource.qq) {
        test(
            'disabling during an in-flight request cancels the previous quality ladder',
            () async {
          dio.interceptors.clear();
          CancelToken? pending;
          dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
            final file =
                (o.data as Map)['req_0']['param']['filename'][0] as String;
            requests.add(file.substring(0, 4));
            if (pending == null) {
              pending = o.cancelToken;
              return;
            }
            h.resolve(Response(requestOptions: o, data: {
              'code': 0,
              'req_0': {
                'code': 0,
                'data': {'midurlinfo': []}
              }
            }));
          }));
          final old = handler.changeQueueLists([song]);
          await settled(() => pending != null);
          await handler.setPlaybackFallback(false);
          await old;
          expect(pending?.isCancelled, isTrue);
          expect(requests.every((q) => q == 'F000'), isTrue);
          expect(handler.playbackState.value.processingState,
              AudioProcessingState.error);
        });
      }
    });
  }
}
