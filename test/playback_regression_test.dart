import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';

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
    await Future<void>.delayed(const Duration(milliseconds: 65));
    expect(player.loadedUrls.length, 2);
    expect(player.position, const Duration(seconds: 12));
    await Future<void>.delayed(const Duration(milliseconds: 65));
    expect(handler.mediaItem.value?.id, 'b');
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
