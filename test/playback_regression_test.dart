import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:bujuan/common/netease_api/src/netease_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_stream_info_test.dart' show flacHeader;

class FakePlayer implements AudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final loadedUrls = <String>[];
  Completer<void>? playingFuture;
  Future<Duration?> Function(AudioSource)? loadCallback;
  int failLoads = 0;
  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  Duration position = Duration.zero;
  @override
  Duration get bufferedPosition => position;
  @override
  double get speed => 1;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;

  void emit() => states.add(PlayerState(playing, processingState));
  void complete() {
    processingState = ProcessingState.completed;
    emit();
  }

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true,
      int? initialIndex,
      Duration? initialPosition}) async {
    if (source is UriAudioSource) loadedUrls.add(source.uri.toString());
    if (failLoads > 0) {
      failLoads--;
      throw StateError('Network failed');
    }
    final duration = loadCallback == null
        ? const Duration(minutes: 3)
        : await loadCallback!(source);
    processingState = ProcessingState.ready;
    position = initialPosition ?? Duration.zero;
    emit();
    return duration;
  }

  @override
  Future<void> play() {
    playing = true;
    playingFuture = Completer<void>();
    emit();
    return playingFuture!.future;
  }

  @override
  Future<void> pause() async {
    playing = false;
    if (playingFuture?.isCompleted == false) playingFuture!.complete();
    emit();
  }

  @override
  Future<void> stop() async {
    await pause();
    processingState = ProcessingState.idle;
    emit();
  }

  @override
  Future<void> seek(Duration? value, {int? index}) async {
    position = value ?? Duration.zero;
    positions.add(position);
  }

  @override
  Future<void> dispose() async {
    await events.close();
    await states.close();
    await positions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const songs = [
  MediaItem(id: 'a', title: 'Song A'),
  MediaItem(id: 'b', title: 'Song B'),
  MediaItem(id: 'c', title: 'Song C')
];
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 15));

class TestApiPaths extends PathProvider {
  TestApiPaths(this.path);
  final String path;
  @override
  Future<void> init() async {}
  @override
  String getDataSavedPath() => '$path/api-data/';
  @override
  String getCookieSavedPath() => '$path/api-cookies/';
}

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Box box;
  late FakePlayer player;
  late BujuanAudioHandler handler;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bujuan-regression-');
    Hive.init(dir.path);
    box = await Hive.openBox('test');
    player = FakePlayer();
    handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        urlResolver: (song) async =>
            'https://example.test/${song.id}.mp3?token=signed');
  });
  tearDown(() async {
    await handler.dispose();
    await box.close();
    await dir.delete(recursive: true);
  });

  test('local music uses its file path without a remote URL lookup', () async {
    await handler.dispose();
    player = FakePlayer();
    handler = BujuanAudioHandler(player: player, box: box, restoreQueue: false);
    final file = File('${dir.path}/local music.wav');
    await file.writeAsBytes([1, 2, 3]);
    final song = MediaItem(
        id: 'local-1',
        title: 'Local test',
        extras: {'type': 'local', 'url': file.path});
    await handler.changeQueueLists([song]);
    expect(player.loadedUrls, [file.uri.toString()]);
    expect(handler.mediaItem.value?.id, song.id);
    expect(player.playing, isTrue);
  });

  test('obsolete Unblock preferences cannot bypass a valid official URL',
      () async {
    final originalInterceptors = Https.dio.interceptors.toList();
    await NeteaseMusicApi.init(provider: TestApiPaths(dir.path));
    await handler.dispose();
    player = FakePlayer();
    handler = BujuanAudioHandler(player: player, box: box, restoreQueue: false);
    await box.putAll({unblockSp: true, unblockVipSp: true});
    var officialLookups = 0;
    final offline = InterceptorsWrapper(onRequest: (options, response) {
      officialLookups++;
      response.resolve(Response(requestOptions: options, data: {
        'code': 200,
        'data': [
          {'id': 'vip', 'url': 'https://example.test/official.mp3', 'code': 200}
        ]
      }));
    });
    Https.dio.interceptors.insert(0, offline);
    try {
      await handler.changeQueueLists([
        const MediaItem(id: 'vip', title: '授权歌曲', extras: {'fee': 1})
      ]);
      expect(officialLookups, 1);
      expect(player.loadedUrls, ['https://example.test/official.mp3']);
      expect(player.playing, isTrue);
    } finally {
      Https.dio.interceptors
        ..clear()
        ..addAll(originalInterceptors);
    }
  });

  test('every quality option reaches the actual song URL request', () async {
    final original = Https.dio.interceptors.toList();
    await NeteaseMusicApi.init(provider: TestApiPaths(dir.path));
    await handler.dispose();
    player = FakePlayer();
    handler = BujuanAudioHandler(player: player, box: box, restoreQueue: false);
    final requested = <String>[];
    Https.dio.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (options, response) {
      final level = (options.data as Map)['level'] as String;
      requested.add(level);
      response.resolve(Response(requestOptions: options, data: {
        'code': 200,
        'data': [
          {
            'id': 'quality',
            'url': 'https://example.test/$level.mp3?token=signed'
          }
        ]
      }));
    }));
    try {
      for (final quality in AudioQuality.values) {
        await box.put(audioQualitySp, quality.name);
        await handler
            .changeQueueLists([const MediaItem(id: 'quality', title: '音质测试')]);
        expect(player.loadedUrls.last,
            'https://example.test/${quality.name}.mp3?token=signed');
        expect(player.playing, isTrue);
      }
      expect(requested, AudioQuality.values.map((e) => e.name).toList());
    } finally {
      Https.dio.interceptors
        ..clear()
        ..addAll(original);
    }
  });

  test('unavailable quality falls back without advancing the song', () async {
    final original = Https.dio.interceptors.toList();
    await NeteaseMusicApi.init(provider: TestApiPaths(dir.path));
    await handler.dispose();
    player = FakePlayer();
    handler = BujuanAudioHandler(player: player, box: box, restoreQueue: false);
    await box.put(audioQualitySp, 'hires');
    final requested = <String>[];
    Https.dio.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (options, response) {
      final level = (options.data as Map)['level'] as String;
      requested.add(level);
      response.resolve(Response(requestOptions: options, data: {
        'code': 200,
        'data': [
          {
            'id': 'quality',
            'url': level == 'exhigh' ? 'https://example.test/exhigh.mp3' : null
          }
        ]
      }));
    }));
    try {
      await handler
          .changeQueueLists([const MediaItem(id: 'quality', title: '音质回退')]);
      expect(requested, ['hires', 'lossless', 'exhigh']);
      expect(handler.mediaItem.value!.id, 'quality');
      expect(player.loadedUrls, ['https://example.test/exhigh.mp3']);
      expect(player.playing, isTrue);
    } finally {
      Https.dio.interceptors
        ..clear()
        ..addAll(original);
    }
  });

  test(
      'quality changes retain position and pause state; local files are not reloaded',
      () async {
    final original = Https.dio.interceptors.toList();
    await NeteaseMusicApi.init(provider: TestApiPaths(dir.path));
    await handler.dispose();
    player = FakePlayer();
    handler = BujuanAudioHandler(player: player, box: box, restoreQueue: false);
    Https.dio.interceptors.insert(0,
        InterceptorsWrapper(onRequest: (options, response) {
      final level = (options.data as Map)['level'] as String;
      response.resolve(Response(requestOptions: options, data: {
        'code': 200,
        'data': [
          {'id': 'quality', 'url': 'https://example.test/$level.mp3'}
        ]
      }));
    }));
    try {
      await handler
          .changeQueueLists([const MediaItem(id: 'quality', title: '同一首歌')]);
      await handler.seek(const Duration(seconds: 51));
      await handler.pause();
      await handler.setAudioQuality(AudioQuality.lossless);
      expect(box.get(audioQualitySp), 'lossless');
      expect(player.loadedUrls.last, 'https://example.test/lossless.mp3');
      expect(player.position, const Duration(seconds: 51));
      expect(player.playing, isFalse);
      await handler.play();
      await handler.setAudioQuality(AudioQuality.hires);
      expect(player.position, const Duration(seconds: 51));
      expect(player.playing, isTrue);
      final local = await File('${dir.path}/local.wav').writeAsBytes([1, 2, 3]);
      await handler.changeQueueLists([
        MediaItem(
            id: 'local',
            title: '本地',
            extras: {'type': 'local', 'url': local.path})
      ]);
      final count = player.loadedUrls.length;
      await handler.setAudioQuality(AudioQuality.standard);
      expect(player.loadedUrls.length, count);
      expect(player.playing, isTrue);
    } finally {
      Https.dio.interceptors
        ..clear()
        ..addAll(original);
    }
  });

  test('quality report verifies the exact loaded file and exposes a server downgrade', () async {
    final original = Https.dio.interceptors.toList();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    server.listen((request) async {
      requests.add(request.uri.toString());
      final bytes = flacHeader(rate: 44100, bits: 16);
      request.response.statusCode = 206;
      request.response.headers.set('content-range', 'bytes 0-${bytes.length - 1}/10000000');
      request.response.add(bytes);
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server.port}/actual.flac?token=retained';
    await NeteaseMusicApi.init(provider: TestApiPaths(dir.path));
    await handler.dispose();
    player = FakePlayer();
    handler = BujuanAudioHandler(player: player, box: box, restoreQueue: false);
    await box.put(audioQualitySp, 'hires');
    Https.dio.interceptors.insert(0, InterceptorsWrapper(onRequest: (options, response) {
      response.resolve(Response(requestOptions: options, data: {'code': 200, 'data': [
        {'id': 'quality', 'url': url, 'level': 'lossless', 'type': 'flac', 'br': 800000, 'size': 10000000}
      ]}));
    }));
    final verified = Completer<void>();
    handler.qualityReport.addListener(() {
      if (handler.qualityReport.value?.checked == true && !verified.isCompleted) verified.complete();
    });
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        await handler.changeQueueLists([const MediaItem(id: 'quality', title: '实际文件')]);
        await verified.future.timeout(const Duration(seconds: 5));
      }, _RealHttpOverrides());
      expect(player.loadedUrls.single, url);
      expect(requests.single, '/actual.flac?token=retained');
      final report = handler.qualityReport.value!;
      expect(report.returnedLevel, 'lossless');
      expect(report.requested, AudioQuality.hires);
      expect((report.stream!.bits, report.stream!.sampleRate), (16, 44100));
      expect(report.description, contains('接口标记与设置不同'));
      expect(player.playing, isTrue);
    } finally {
      await server.close(force: true);
      Https.dio.interceptors..clear()..addAll(original);
    }
  });

  test('queue insertion preserves the playing song and survives shuffle',
      () async {
    await handler.changeQueueLists(songs, index: 1);
    const added = MediaItem(id: 'inserted', title: 'Inserted song');
    await handler.insertQueueItem(0, added);
    expect(handler.playbackState.value.queueIndex, 2);
    expect(handler.mediaItem.value?.id, 'b');
    expect(player.loadedUrls, hasLength(1));
    await handler.setRepeatMode(AudioServiceRepeatMode.none);
    expect(handler.queue.value.map((song) => song.id), contains(added.id));
    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    expect(handler.queue.value.map((song) => song.id),
        ['inserted', 'a', 'b', 'c']);
    expect(handler.playbackState.value.queueIndex, 2);
    expect(handler.mediaItem.value?.id, 'b');
  });

  test('late URL response cannot overwrite a newer selection', () async {
    await handler.dispose();
    player = FakePlayer();
    final a = Completer<String?>();
    handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        urlResolver: (song) =>
            song.id == 'a' ? a.future : Future.value('https://example.test/b'));
    final first = handler.changeQueueLists(songs);
    await settle();
    await handler.skipToQueueItem(1);
    a.complete('https://example.test/a');
    await first;
    expect(player.loadedUrls, ['https://example.test/b']);
    expect(handler.mediaItem.value?.id, 'b');
    expect(handler.playbackState.value.queueIndex, 1);
  });

  test('pause during URL lookup prevents automatic playback', () async {
    await handler.dispose();
    player = FakePlayer();
    final url = Completer<String?>();
    handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        urlResolver: (_) => url.future);
    final pending = handler.changeQueueLists(songs);
    await settle();
    await handler.pause();
    url.complete('https://example.test/a');
    await pending;
    expect(player.playing, false);
    expect(handler.playbackState.value.playing, false);
  });

  test('stop invalidates outstanding URL lookup', () async {
    await handler.dispose();
    player = FakePlayer();
    final url = Completer<String?>();
    handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        urlResolver: (_) => url.future);
    final pending = handler.changeQueueLists(songs);
    await settle();
    await handler.stop();
    url.complete('https://example.test/a');
    await pending;
    expect(player.loadedUrls, isEmpty);
    expect(player.playing, false);
  });

  test('all unavailable songs terminate even in repeat-one mode', () async {
    await handler.dispose();
    player = FakePlayer();
    var requests = 0;
    handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        urlResolver: (_) async {
          requests++;
          return null;
        });
    await handler.setRepeatMode(AudioServiceRepeatMode.one);
    await handler.changeQueueLists(songs).timeout(const Duration(seconds: 2));
    expect(requests, songs.length);
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.error);
    expect(handler.playbackState.value.playing, false);
    expect(handler.mediaItem.value?.id,
        songs[handler.playbackState.value.queueIndex!].id);
  });

  test('failed native load retries and preserves signed URL', () async {
    player.failLoads = 1;
    await handler.changeQueueLists(songs);
    expect(player.loadedUrls.length, 2);
    expect(player.loadedUrls.last, 'https://example.test/a.mp3?token=signed');
    expect(player.playing, true);
    expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));
  });

  test('system controls acknowledge play and toggle immediately', () async {
    await handler.changeQueueLists(songs);
    await handler.pause();
    expect(handler.playbackState.value.controls.map((e) => e.action),
        contains(MediaAction.play));
    await handler.play().timeout(const Duration(milliseconds: 100));
    expect(handler.playbackState.value.playing, true);
    await handler.click();
    expect(handler.playbackState.value.playing, false);
    expect(handler.playbackState.value.systemActions,
        contains(MediaAction.skipToQueueItem));
  });

  test('TV native fast-forward and rewind seek instead of invoking favorites',
      () async {
    await handler.dispose();
    player = FakePlayer();
    handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        television: true,
        urlResolver: (_) async => 'https://example.test/song.mp3');
    await handler.changeQueueLists(songs);
    expect(handler.playbackState.value.controls.map((e) => e.action),
        containsAll([MediaAction.fastForward, MediaAction.rewind]));
    expect(handler.playbackState.value.androidCompactActionIndices, [0, 1, 2]);
    await handler.seek(const Duration(seconds: 175));
    await handler.fastForward();
    expect(player.position, const Duration(minutes: 3));
    await handler.seek(const Duration(seconds: 5));
    await handler.rewind();
    expect(player.position, Duration.zero);
  });

  test('natural repeat and manual next have different behavior', () async {
    await handler.changeQueueLists(songs);
    await handler.setRepeatMode(AudioServiceRepeatMode.one);
    player.complete();
    await settle();
    expect(handler.mediaItem.value?.id, 'a');
    expect(player.loadedUrls.length, 2);
    await handler.skipToNext();
    expect(handler.mediaItem.value?.id, 'b');
    await handler.skipToPrevious();
    expect(handler.mediaItem.value?.id, 'a');
    await handler.skipToPrevious();
    expect(handler.mediaItem.value?.id, 'c');
  });

  test('empty queue and invalid indices are safe', () async {
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.skipToQueueItem(-1);
    await handler.changeQueueLists([]);
    await handler.play();
    expect(handler.queue.value, isEmpty);
    expect(handler.mediaItem.value, isNull);
    await handler.changeQueueLists(songs, index: 999);
    expect(handler.mediaItem.value?.id, 'c');
    await handler.skipToQueueItem(999);
    expect(handler.mediaItem.value?.id, 'c');
  });

  test('favorite updates preserve processing state and current identity',
      () async {
    await handler.changeQueueLists(songs);
    await handler
        .updateMediaItem(songs.first.copyWith(extras: {'liked': true}));
    expect(handler.playbackState.value.processingState,
        AudioProcessingState.ready);
    expect(handler.mediaItem.value?.extras?['liked'], true);
    await handler.skipToNext();
    await handler
        .updateMediaItem(songs.first.copyWith(extras: {'liked': false}));
    expect(handler.mediaItem.value?.id, 'b');
  });

  test('shuffle and removal keep the active queue index aligned', () async {
    await handler.changeQueueLists(songs, index: 1);
    await handler.setShuffleMode(AudioServiceShuffleMode.all);
    expect(
        handler.queue.value[handler.playbackState.value.queueIndex!].id, 'b');
    await handler.setShuffleMode(AudioServiceShuffleMode.none);
    await handler.removeQueueItemAt(0);
    expect(handler.queue.value.map((e) => e.id), ['b', 'c']);
    expect(handler.playbackState.value.queueIndex, 0);
  });

  test('source mutations remain ordered during rapid switching', () async {
    final pendingSource = Completer<Duration?>();
    player.loadCallback = (_) => pendingSource.future;
    final first = handler.changeQueueLists(songs);
    await settle();
    final second = handler.skipToNext();
    player.loadCallback = null;
    pendingSource.complete(const Duration(minutes: 3));
    await Future.wait([first, second]);
    expect(handler.mediaItem.value?.id, 'b');
    expect(player.loadedUrls.last, contains('/b.mp3'));
    expect(player.playing, true);
  });

  test('repeat mode change during loading preserves the requested song',
      () async {
    await handler.dispose();
    player = FakePlayer();
    final b = Completer<String?>();
    handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        urlResolver: (song) => song.id == 'b'
            ? b.future
            : Future.value('https://example.test/${song.id}'));
    await handler.changeQueueLists(songs);
    final selection = handler.playIndex(1);
    final reorder = handler.setShuffleMode(AudioServiceShuffleMode.all);
    await settle();
    b.complete('https://example.test/b');
    await Future.wait([selection, reorder]);
    expect(handler.mediaItem.value?.id, 'b');
    expect(
        handler.queue.value[handler.playbackState.value.queueIndex!].id, 'b');
    expect(player.loadedUrls.last, 'https://example.test/b');
  });

  test('URL timeout skips to the next playable item', () async {
    await handler.dispose();
    player = FakePlayer();
    handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        loadTimeout: const Duration(milliseconds: 20),
        urlResolver: (song) => song.id == 'a'
            ? Completer<String?>().future
            : Future.value('https://example.test/${song.id}'));
    await handler.changeQueueLists(songs);
    expect(handler.mediaItem.value?.id, 'b');
    expect(player.playing, true);
  });

  test('native timeout is stopped before retry', () async {
    await handler.dispose();
    player = FakePlayer();
    var attempts = 0;
    player.loadCallback = (_) {
      if (attempts++ == 0) return Completer<Duration?>().future;
      return Future.value(const Duration(minutes: 3));
    };
    handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        loadTimeout: const Duration(milliseconds: 20),
        urlResolver: (song) async => 'https://example.test/${song.id}');
    await handler.changeQueueLists(songs);
    expect(attempts, 2);
    expect(handler.mediaItem.value?.id, 'a');
    expect(player.playing, true);
  });

  test('stalled playback reloads at position and then advances', () async {
    await handler.dispose();
    player = FakePlayer();
    handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        watchdogInterval: const Duration(milliseconds: 10),
        stallTimeout: const Duration(milliseconds: 40),
        urlResolver: (song) async => 'https://example.test/${song.id}');
    await handler.changeQueueLists(songs);
    await handler.seek(const Duration(seconds: 12));
    await player.playerStateStream
        .firstWhere((state) => state.playing && player.loadedUrls.length == 2)
        .timeout(const Duration(seconds: 2));
    expect(player.loadedUrls.length, 2);
    expect(player.position, const Duration(seconds: 12));
    // Metadata is published before the source finishes loading. Pause once
    // playback actually starts, rather than racing an unfinished recovery.
    await player.playerStateStream
        .firstWhere(
            (state) => state.playing && handler.mediaItem.value?.id == 'b')
        .timeout(const Duration(seconds: 2));
    expect(handler.mediaItem.value?.id, 'b');
    // Leave the synchronous fake stream callback before emitting pause.
    await Future<void>.delayed(Duration.zero);
    await handler.pause();
    final loadCount = player.loadedUrls.length;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(player.loadedUrls.length, loadCount);
    expect(player.playing, false);
  });

  test('encrypted cache returns positive byte ranges and MIME type', () async {
    final file = File('${dir.path}/cache.flac');
    await file.writeAsBytes([1, 2, 3, 4, 5].map((e) => e ^ 0xa3).toList());
    final response = await StreamSource(file.path, 'flac').request(1, 4);
    expect(response.sourceLength, 5);
    expect(response.contentLength, 3);
    expect(response.offset, 1);
    expect(response.contentType, 'audio/flac');
    expect(await response.stream.expand((e) => e).toList(), [2, 3, 4]);
  });
}
