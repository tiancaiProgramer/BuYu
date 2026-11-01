// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';

import 'playback_regression_test.dart' show FakePlayer;

const track = MediaItem(
    id: 'qq:first',
    title: 'QQ song',
    artist: 'QQ artist',
    extras: {'source': 'qq', 'mid': 'first', 'mediaMid': 'media'});
const nextTrack = MediaItem(
    id: 'qq:next',
    title: 'Next QQ song',
    extras: {'source': 'qq', 'mid': 'next', 'mediaMid': 'nextmedia'});

String filename(RequestOptions options) =>
    (options.data as Map)['req_0']['param']['filename'][0] as String;

Response<dynamic> reply(RequestOptions options, {String? purl}) =>
    Response(requestOptions: options, data: {
      'code': 0,
      'req_0': {
        'code': 0,
        'data': {
          'sip': ['https://dl.stream.qqmusic.qq.com/'],
          'midurlinfo': [
            {'purl': purl ?? '${filename(options)}?vkey=retained'}
          ]
        }
      }
    });

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: 'Playback operation did not settle');
}

class ImmediateFailurePlayer extends FakePlayer {
  @override
  Future<void> play() {
    if (!loadedUrls.last.contains('M500')) {
      return Future<void>.error(StateError('Immediate native play error'));
    }
    return super.play();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QQ official URL quality fallback', () {
    for (final failure in [
      'service error',
      'network error',
      'invalid JSON',
      'empty URL',
      'trial URL',
      'foreign URL'
    ]) {
      test('$failure on Hi-Res continues with lossless', () async {
        final dio = Dio();
        final requests = <String>[];
        dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          final file = filename(o);
          requests.add(file.substring(0, 4));
          if (file.startsWith('RS01')) {
            switch (failure) {
              case 'service error':
                h.resolve(Response(requestOptions: o, data: {
                  'code': 0,
                  'req_0': {'code': 403}
                }));
              case 'network error':
                h.reject(DioException(
                    requestOptions: o, type: DioExceptionType.connectionError));
              case 'invalid JSON':
                h.resolve(Response(requestOptions: o, data: '{broken'));
              case 'empty URL':
                h.resolve(reply(o, purl: ''));
              case 'trial URL':
                h.resolve(reply(o, purl: 'RS02trial.flac'));
              default:
                h.resolve(
                    reply(o, purl: 'https://example.test/RS01media.flac'));
            }
          } else {
            h.resolve(reply(o));
          }
        }));
        final qq = QqMusic(dio: dio);
        try {
          final audio = await qq.audio(track, AudioQuality.hires);
          expect(requests, ['RS01', 'F000']);
          expect(audio.quality, AudioQuality.lossless);
          expect(audio.url, endsWith('F000media.flac?vkey=retained'));
        } finally {
          qq.dispose();
        }
      });
    }

    test('timed out Hi-Res request is cancelled before lower quality succeeds',
        () async {
      final dio = Dio();
      final requests = <String>[];
      CancelToken? highToken;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(filename(o).substring(0, 4));
        if (filename(o).startsWith('RS01')) {
          highToken = o.cancelToken; // Deliberately never completes.
        } else {
          h.resolve(reply(o));
        }
      }));
      final qq = QqMusic(dio: dio);
      try {
        final audio = await qq.audio(track, AudioQuality.hires,
            qualityTimeout: const Duration(milliseconds: 30));
        expect(highToken?.isCancelled, isTrue);
        expect(audio.quality, AudioQuality.lossless);
        expect(requests, ['RS01', 'F000']);
      } finally {
        qq.dispose();
      }
    });

    test('per-quality diagnostics do not silently downgrade', () async {
      final dio = Dio();
      final requests = <String>[];
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(filename(o).substring(0, 4));
        h.resolve(reply(o, purl: ''));
      }));
      final qq = QqMusic(dio: dio);
      try {
        await expectLater(
            qq.audio(track, AudioQuality.hires, allowFallback: false),
            throwsA(isA<MusicServiceError>()));
        expect(requests, ['RS01']);
      } finally {
        qq.dispose();
      }
    });

    test('all unavailable qualities are tried once per distinct format',
        () async {
      final dio = Dio();
      final requests = <String>[];
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(filename(o).substring(0, 4));
        h.resolve(Response(requestOptions: o, data: {'code': 403}));
      }));
      final qq = QqMusic(dio: dio);
      try {
        await expectLater(qq.audio(track, AudioQuality.hires),
            throwsA(isA<MusicServiceError>()));
        expect(requests, ['RS01', 'F000', 'M800', 'M500']);
      } finally {
        qq.dispose();
      }
    });

    test('cancelling the selection does not trigger lower quality requests',
        () async {
      final dio = Dio();
      final requests = <String>[];
      final cancel = CancelToken();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(filename(o));
        cancel.cancel('User selected a different song');
      }));
      final qq = QqMusic(dio: dio);
      try {
        await expectLater(
            qq.audio(track, AudioQuality.hires, cancelToken: cancel),
            throwsA(isA<DioException>()
                .having((e) => e.type, 'type', DioExceptionType.cancel)));
        expect(requests, hasLength(1));
      } finally {
        qq.dispose();
      }
    });

    test('manual lower quality is an upper bound, including server responses',
        () async {
      final dio = Dio();
      final requests = <String>[];
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(filename(o).substring(0, 4));
        h.resolve(reply(o,
            purl:
                filename(o).startsWith('M800') ? 'RS01unexpected.flac' : null));
      }));
      final qq = QqMusic(dio: dio);
      try {
        final audio = await qq.audio(track, AudioQuality.exhigh);
        expect(audio.quality, AudioQuality.standard);
        expect(requests, ['M800', 'M500']);
      } finally {
        qq.dispose();
      }
    });
  });

  group('QQ player quality fallback', () {
    late Directory dir;
    late Box box;
    late Dio dio;
    late QqMusic qq;
    late FakePlayer player;
    late BujuanAudioHandler handler;
    late List<String> requests;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('buyu-qq-quality-');
      Hive.init(dir.path);
      box = await Hive.openBox('qq-quality');
      await box.put(audioQualitySp, AudioQuality.hires.name);
      requests = [];
      dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(filename(o));
        h.resolve(reply(o));
      }));
      qq = QqMusic(dio: dio);
      GetIt.I.registerSingleton<QqMusic>(qq);
      player = FakePlayer();
      handler =
          BujuanAudioHandler(player: player, box: box, restoreQueue: false);
    });
    tearDown(() async {
      await handler.dispose();
      qq.dispose();
      await GetIt.I.reset();
      await box.close();
      await dir.delete(recursive: true);
    });

    test(
        'CDN or decoder failure falls back on the same song and keeps preference',
        () async {
      player.loadCallback = (source) async {
        if ((source as UriAudioSource).uri.path.contains('F000')) {
          throw StateError('High quality CDN/decoder rejected the file');
        }
        return const Duration(minutes: 3);
      };
      await handler.changeQueueLists([track, nextTrack]);
      expect(requests, ['F000media.flac', 'M800media.mp3']);
      expect(handler.mediaItem.value?.id, track.id);
      expect(handler.mediaItem.value?.artist, track.artist);
      expect(handler.qualityReport.value?.requested, AudioQuality.lossless);
      expect(handler.qualityReport.value?.returnedLevel, 'exhigh');
      expect(box.get(audioQualitySp), 'hires');
      expect(player.playing, isTrue);
      await handler.skipToNext();
      expect(requests.last, 'M800nextmedia.mp3');
      expect(requests, contains('F000nextmedia.flac'));
    });

    test('falls through all high formats to standard without skipping the song',
        () async {
      player.loadCallback = (source) async {
        if (!(source as UriAudioSource).uri.path.contains('M500')) {
          throw StateError('Only standard quality is playable');
        }
        return const Duration(minutes: 3);
      };
      await handler.changeQueueLists([track, nextTrack]);
      expect(requests, ['F000media.flac', 'M800media.mp3', 'M500media.mp3']);
      expect(handler.mediaItem.value?.id, track.id);
      expect(handler.qualityReport.value?.returnedLevel, 'standard');
      expect(player.playing, isTrue);
    });

    test(
        'exhausted formats advance once and next song starts at preferred quality',
        () async {
      player.loadCallback = (source) async {
        if (!(source as UriAudioSource).uri.path.contains('nextmedia')) {
          throw StateError('First song unavailable in every format');
        }
        return const Duration(minutes: 3);
      };
      await handler.changeQueueLists([track, nextTrack]);
      expect(requests, [
        'F000media.flac',
        'M800media.mp3',
        'M500media.mp3',
        'M500media.mp3',
        'F000nextmedia.flac'
      ]);
      expect(handler.mediaItem.value?.id, nextTrack.id);
      expect(handler.qualityReport.value?.returnedLevel, 'lossless');
      expect(player.playing, isTrue);
    });

    test(
        'asynchronous playback errors downgrade repeatedly and preserve position',
        () async {
      await handler.changeQueueLists([track, nextTrack]);
      for (final level in ['exhigh', 'standard', 'standard']) {
        final before = requests.length;
        await player.seek(const Duration(seconds: 42));
        player.events.addError(StateError('CDN failed during playback'));
        await until(() =>
            requests.length > before &&
            player.playing &&
            handler.qualityReport.value?.returnedLevel == level);
        expect(handler.mediaItem.value?.id, track.id);
        expect(player.position, const Duration(seconds: 42));
      }
      expect(requests, [
        'F000media.flac',
        'M800media.mp3',
        'M500media.mp3',
        'M500media.mp3'
      ]);
      expect(box.get(audioQualitySp), 'hires');
    });

    test(
        'immediate native play failures continue through the full quality ladder',
        () async {
      await handler.dispose();
      player = ImmediateFailurePlayer();
      handler =
          BujuanAudioHandler(player: player, box: box, restoreQueue: false);
      await handler.changeQueueLists([track, nextTrack]);
      await until(() =>
          player.playing &&
          handler.qualityReport.value?.returnedLevel == 'standard');
      expect(requests, ['F000media.flac', 'M800media.mp3', 'M500media.mp3']);
      expect(handler.mediaItem.value?.id, track.id);
    });

    test(
        'switching songs cancels a pending high format and ignores its fallbacks',
        () async {
      dio.interceptors.clear();
      CancelToken? oldToken;
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(filename(o));
        if (filename(o) == 'F000media.flac') {
          oldToken = o.cancelToken;
        } else {
          h.resolve(reply(o));
        }
      }));
      final old = handler.changeQueueLists([track, nextTrack]);
      await until(() => oldToken != null);
      await handler.skipToNext();
      await old;
      expect(oldToken?.isCancelled, isTrue);
      expect(requests, ['F000media.flac', 'F000nextmedia.flac']);
      expect(handler.mediaItem.value?.id, nextTrack.id);
      expect(player.playing, isTrue);
    });
  });
}
