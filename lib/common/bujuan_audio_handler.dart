import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/constants/enmu.dart';
import 'package:bujuan/common/constants/other.dart';

import 'package:bujuan/pages/home/home_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_player_handler.dart';
import 'audio_quality.dart';
import 'audio_stream_info.dart';
import 'display_mode.dart';
import 'constants/key.dart';
import 'constants/platform_utils.dart';
import 'netease_api/src/netease_api.dart';

Future<List<MediaItem>> getCachePlayList(RootIsolateData data) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(data.rootIsolateToken);
  List<MediaItem> items = data.playlist?.map((e) {
        var map = MediaItemMessage.fromMap(jsonDecode(e));
        return MediaItem(
          id: map.id,
          duration: map.duration,
          artUri: map.artUri,
          extras: map.extras,
          title: map.title,
          artist: map.artist,
          album: map.album,
        );
      }).toList() ??
      [];
  return items;
}

Future<List<String>> setCachePlayList(RootIsolateData data) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(data.rootIsolateToken);
  return data.items
          ?.map((e) => jsonEncode(MediaItemMessage(
                id: e.id,
                album: e.album,
                title: e.title,
                artist: e.artist,
                duration: e.duration,
                artUri: e.artUri,
                extras: e.extras,
              ).toMap()))
          .toList() ??
      [];
}

class RootIsolateData {
  RootIsolateToken rootIsolateToken;
  List<String>? playlist;
  List<MediaItem>? items;

  RootIsolateData(this.rootIsolateToken, {this.playlist, this.items});
}

class _ResolvedAudio {
  const _ResolvedAudio(this.url, this.report);
  final String url;
  final AudioQualityReport report;
}

class BujuanAudioHandler extends BaseAudioHandler
    with SeekHandler, QueueHandler
    implements AudioPlayerHandler {
  final AudioPlayer _player;
  final Box _box;
  final Future<String?> Function(MediaItem)? _urlResolver;
  final Duration loadTimeout;
  final Duration stallTimeout;
  final bool _television;
  final _subscriptions = <StreamSubscription>[];
  AudioServiceRepeatMode _audioServiceRepeatMode = AudioServiceRepeatMode.all;
  final _playList = <MediaItem>[];
  int _curIndex = 0;
  int _request = 0;
  bool _loading = false;
  bool _loaded = false;
  bool _wantsPlay = false;
  bool _recovering = false;
  bool _disposed = false;
  int _recoveries = 0;
  Duration _lastPosition = Duration.zero;
  DateTime _lastProgress = DateTime.now();
  Future<void> _playerOperation = Future.value();
  Timer? _sleepTimer;
  Timer? _watchdog;
  final qualityReport = ValueNotifier<AudioQualityReport?>(null);
  AudioStreamProbe? _streamProbe;

  BujuanAudioHandler({
    AudioPlayer? player,
    Box? box,
    Future<String?> Function(MediaItem)? urlResolver,
    this.loadTimeout = const Duration(seconds: 15),
    this.stallTimeout = const Duration(seconds: 25),
    bool restoreQueue = true,
    bool? television,
    Duration watchdogInterval = const Duration(seconds: 5),
  })  : _player = player ?? GetIt.instance<AudioPlayer>(),
        _box = box ?? GetIt.instance<Box>(),
        _urlResolver = urlResolver,
        _television = television ?? DisplayMode.isTv {
    _subscriptions.add(_player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object error, StackTrace stack) {
        if (!_loading && _wantsPlay) unawaited(_recover());
      },
    ));
    // Playing changes do not always produce a playback event (e.g. pause).
    _subscriptions.add(_player.playerStateStream.listen((state) {
      _broadcastState();
      if (!_loading &&
          _loaded &&
          _wantsPlay &&
          state.processingState == ProcessingState.completed) {
        unawaited(_advance(completed: true));
      }
    }));
    _subscriptions.add(_player.positionStream.listen((position) {
      if (position != _lastPosition || !_player.playing) {
        _lastPosition = position;
        _lastProgress = DateTime.now();
      }
    }));
    _watchdog = Timer.periodic(watchdogInterval, (_) {
      if (!_loading &&
          _loaded &&
          _wantsPlay &&
          _player.playing &&
          DateTime.now().difference(_lastProgress) >= stallTimeout) {
        unawaited(_recover());
      }
    });
    if (restoreQueue) unawaited(_loadPlaylistByStorage());
  }

  bool _isCurrent(int request) => !_disposed && request == _request;

  // Only source mutations are serialized. Network requests may finish in any
  // order; their generation is checked before touching the player.
  Future<void> _withPlayer(Future<void> Function() action) {
    final operation = _playerOperation.then((_) => action());
    _playerOperation = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _loadPlaylistByStorage() async {
    final request = _request;
    try {
      final mode = _box.get(repeatModeSp, defaultValue: 'all');
      _audioServiceRepeatMode = AudioServiceRepeatMode.values
              .firstWhereOrNull((element) => element.name == mode) ??
          AudioServiceRepeatMode.all;
      final stored =
          List<String>.from(_box.get(playQueue, defaultValue: <String>[]));
      final items = stored.map((e) {
        final m = MediaItemMessage.fromMap(jsonDecode(e));
        return MediaItem(
            id: m.id,
            title: m.title,
            album: m.album,
            artist: m.artist,
            duration: m.duration,
            artUri: m.artUri,
            extras: m.extras);
      }).toList();
      if (_isCurrent(request) && items.isNotEmpty) {
        final savedId = _box.get(playById);
        final index = items.indexWhere((e) => e.id == savedId);
        await changeQueueLists(items,
            init: true,
            index: index >= 0 ? index : (_box.get(playByIndex) ?? 0));
      }
    } catch (error) {
      debugPrint('Unable to restore playback queue: $error');
    }
  }

  void _broadcastState({AudioProcessingState? state, String? error}) {
    if (_disposed) return;
    final playing = _loading ? _wantsPlay : _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        if (!_television)
          PlatformUtils.isAndroid
              ? ((mediaItem.value?.extras?['liked'] ?? false)
                  ? const MediaControl(
                      label: 'fastForward',
                      action: MediaAction.fastForward,
                      androidIcon: 'drawable/audio_service_like')
                  : const MediaControl(
                      label: 'rewind',
                      action: MediaAction.rewind,
                      androidIcon: 'drawable/audio_service_unlike'))
              : const MediaControl(
                  label: 'setRating',
                  action: MediaAction.setRating,
                  androidIcon: 'drawable/audio_service_like'),
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        if (_television) MediaControl.rewind,
        if (_television) MediaControl.fastForward,
        MediaControl.stop,
      ],
      systemActions: {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.seek,
        MediaAction.skipToPrevious,
        MediaAction.skipToNext,
        MediaAction.skipToQueueItem,
        if (_television) MediaAction.rewind,
        if (_television) MediaAction.fastForward,
      },
      androidCompactActionIndices:
          _television ? const [0, 1, 2] : const [1, 2, 3],
      processingState: state ??
          (_loading
              ? AudioProcessingState.loading
              : const {
                  ProcessingState.idle: AudioProcessingState.idle,
                  ProcessingState.loading: AudioProcessingState.loading,
                  ProcessingState.buffering: AudioProcessingState.buffering,
                  ProcessingState.ready: AudioProcessingState.ready,
                  ProcessingState.completed: AudioProcessingState.completed,
                }[_player.processingState]!),
      repeatMode: _audioServiceRepeatMode == AudioServiceRepeatMode.none
          ? AudioServiceRepeatMode.all
          : _audioServiceRepeatMode,
      shuffleMode: _audioServiceRepeatMode == AudioServiceRepeatMode.none
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      playing: playing,
      updatePosition: _loading ? Duration.zero : _player.position,
      bufferedPosition: _loading ? Duration.zero : _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: queue.value.isEmpty ? null : _curIndex,
      errorCode: error == null ? null : 1,
      errorMessage: error,
    ));
  }

  Future<void> _saveQueue() async {
    await _box.put(
        playQueue,
        _playList
            .map((e) => jsonEncode(MediaItemMessage(
                  id: e.id,
                  title: e.title,
                  album: e.album,
                  artist: e.artist,
                  duration: e.duration,
                  artUri: e.artUri,
                  extras: e.extras,
                ).toMap()))
            .toList());
  }

  @override
  Future<void> changeQueueLists(List<MediaItem> list,
      {int index = 0, bool init = false}) async {
    _playList
      ..clear()
      ..addAll(list);
    var ordered = List<MediaItem>.of(list);
    if (ordered.isEmpty) {
      await stop();
      queue.add([]);
      mediaItem.add(null);
      _broadcastState();
      await _saveQueue();
      return;
    }
    index = index.clamp(0, ordered.length - 1);
    final selected = ordered[index];
    if (_audioServiceRepeatMode == AudioServiceRepeatMode.none)
      ordered.shuffle();
    queue.add(ordered);
    // playIndex increments the generation before its first await.
    final loading = playIndex(ordered.indexOf(selected), playIt: !init);
    if (!init) await _saveQueue();
    await loading;
  }

  @override
  Future<void> addFmItems(
      List<MediaItem> mediaItems, bool isAddcurIndex) async {
    if (mediaItems.isEmpty) return;
    final retained = Home.to.fm.value && queue.value.isNotEmpty
        ? [queue.value[_curIndex], ...mediaItems]
        : mediaItems;
    Home.to.fm.value = true;
    await _box.put(fmSp, true);
    queueTitle.add('Fm');
    await changeQueueLists(retained,
        index: isAddcurIndex && retained.length > 1 ? 1 : 0);
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem item) async {
    final updated = List<MediaItem>.of(queue.value);
    index = index.clamp(0, updated.length);
    final before = index < updated.length ? updated[index] : null;
    if (updated.isNotEmpty && index <= _curIndex) _curIndex++;
    updated.insert(index, item);
    final originalIndex = before == null
        ? _playList.length
        : _playList.indexWhere((e) => e.id == before.id);
    _playList.insert(
        originalIndex < 0 ? _playList.length : originalIndex, item);
    queue.add(updated);
    _broadcastState();
    await _box.put(playByIndex, _curIndex);
    await _saveQueue();
  }

  @override
  Future<void> removeQueueItem(MediaItem item) async {
    await removeQueueItemAt(queue.value.indexWhere((e) => e.id == item.id));
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (_loading || index < 0 || index >= queue.value.length) return;
    if (index == _curIndex) {
      WidgetUtil.showToast('正在播放的歌曲无法移除');
      return;
    }
    final updated = List<MediaItem>.of(queue.value);
    final removed = updated.removeAt(index);
    _playList.removeWhere((e) => e.id == removed.id);
    if (index < _curIndex) _curIndex--;
    queue.add(updated);
    await _box.put(playByIndex, _curIndex);
    _broadcastState();
    await _saveQueue();
  }

  @override
  Future<void> updateMediaItem(MediaItem item) async {
    for (var i = 0; i < _playList.length; i++) {
      if (_playList[i].id == item.id) _playList[i] = item;
    }
    final updated = queue.value.map((e) => e.id == item.id ? item : e).toList();
    queue.add(updated);
    if (mediaItem.value?.id == item.id) {
      mediaItem.add(item);
      _broadcastState();
    }
  }

  @override
  Future<void> playIndex(int index, {bool playIt = true}) async {
    if (_disposed || index < 0 || index >= queue.value.length) return;
    _recoveries = 0;
    await _load(index, playIt: playIt);
  }

  @override
  Future<void> readySongUrl({bool isNext = true, bool playIt = true}) async {
    if (queue.value.isNotEmpty)
      await _load(_curIndex, playIt: playIt, next: isNext);
  }

  Future<_ResolvedAudio?> _resolveUrl(MediaItem song) async {
    final preferred = AudioQuality.parse(_box.get(audioQualitySp));
    if (_urlResolver != null) {
      final url = await _urlResolver!(song);
      return url == null || url.isEmpty ? null : _ResolvedAudio(url,
          AudioQualityReport(songId: song.id, title: song.title, requested: preferred));
    }
    if (song.extras?['type'] == MediaType.local.name ||
        song.extras?['type'] == MediaType.neteaseCache.name) {
      final url = song.extras?['url'] as String?;
      return url == null || url.isEmpty ? null : _ResolvedAudio(url,
          AudioQualityReport(songId: song.id, title: song.title, requested: preferred, local: true));
    }
    for (final quality in preferred.fallbacks) {
      try {
        final response = await NeteaseMusicApi()
            .songDownloadUrl([song.id], level: quality.name);
        // Match by id and retain signed query parameters in the CDN URL.
        final item = response.data?.firstWhereOrNull((e) => e.id == song.id);
        final url = item?.url;
        if (url != null && url.isNotEmpty) return _ResolvedAudio(url,
            AudioQualityReport(songId: song.id, title: song.title,
                requested: preferred, returnedLevel: item!.level,
                bitrate: item.br, size: item.size,
                serverFormat: item.type ?? item.encodeType,
                trial: item.freeTrialInfo != null));
      } catch (_) {
        if (quality == AudioQuality.standard) rethrow;
      }
    }
    return null;
  }

  Future<void> _verifyAudio(_ResolvedAudio resolved, int request) async {
    final probe = AudioStreamProbe();
    _streamProbe = probe;
    try {
      final info = await probe.inspect(resolved.url);
      if (_isCurrent(request)) {
        qualityReport.value = resolved.report.verified(info);
        debugPrint('BuJuan audio verification: ${qualityReport.value!.description}');
      }
    } catch (_) {
      if (_isCurrent(request)) qualityReport.value = resolved.report.verified(null,
          error: '实际文件核验未完成，不能确认音频规格');
    } finally {
      probe.close();
      if (identical(_streamProbe, probe)) _streamProbe = null;
    }
  }

  Future<void> setAudioQuality(AudioQuality quality) async {
    if (AudioQuality.parse(_box.get(audioQualitySp)) == quality) return;
    await _box.put(audioQualitySp, quality.name);
    if (_disposed || queue.value.isEmpty) return;
    final song = queue.value[_curIndex];
    if (song.extras?['type'] == MediaType.local.name ||
        song.extras?['type'] == MediaType.neteaseCache.name) return;
    final position = _loading ? Duration.zero : _player.position;
    _recoveries = 0;
    await _load(_curIndex, playIt: _wantsPlay, position: position);
  }

  Future<void> _load(int index,
      {required bool playIt,
      bool next = true,
      Duration position = Duration.zero}) async {
    final request = ++_request;
    _streamProbe?.close();
    qualityReport.value = null;
    _curIndex = index;
    _wantsPlay = playIt;
    _loading = true;
    _loaded = false;
    _broadcastState();
    // Bound failures to one pass of the queue. A fully unavailable playlist
    // must stop, including when single-track repeat is selected.
    final count = queue.value.length;
    for (var visited = 0; visited < count && _isCurrent(request); visited++) {
      final song = queue.value[_curIndex];
      for (var attempt = 0; attempt < 2 && _isCurrent(request); attempt++) {
        try {
          await _withPlayer(() async {
            if (!_isCurrent(request)) return;
            await _player.stop();
            if (!_isCurrent(request)) return;
            mediaItem.add(song);
            _broadcastState();
          });
          if (!_isCurrent(request)) return;
          final resolved = await _resolveUrl(song).timeout(loadTimeout);
          if (!_isCurrent(request)) return;
          if (resolved == null) break;
          final url = resolved.url;
          await _withPlayer(() async {
            if (!_isCurrent(request)) return;
            final AudioSource source;
            if (song.extras?['type'] == MediaType.local.name) {
              final uri = Uri.parse(url);
              source = uri.scheme == 'content' ? AudioSource.uri(uri, tag: song) : AudioSource.file(uri.scheme == 'file' ? uri.toFilePath() : url, tag: song);
            } else if (song.extras?['type'] == MediaType.neteaseCache.name) {
              source =
                  StreamSource(url, url.replaceAll('.uc!', '').split('.').last);
            } else {
              source = AudioSource.uri(Uri.parse(url), tag: song);
            }
            Duration? actualDuration;
            try {
              actualDuration = await _player
                  .setAudioSource(source, initialPosition: position)
                  .timeout(loadTimeout);
            } on TimeoutException {
              // timeout does not cancel a native load; stop it before the next.
              await _player.stop();
              rethrow;
            }
            if (!_isCurrent(request)) return;
            final loadedSong = actualDuration == null
                ? song
                : song.copyWith(duration: actualDuration);
            final updated = List<MediaItem>.of(queue.value);
            updated[_curIndex] = loadedSong;
            queue.add(updated);
            mediaItem.add(loadedSong);
            _loaded = true;
            _loading = false;
            qualityReport.value = resolved.report;
            unawaited(_verifyAudio(resolved, request));
            _lastPosition = _player.position;
            _lastProgress = DateTime.now();
            await _box.put(playByIndex, _curIndex);
            await _box.put(playById, song.id);
            if (!_isCurrent(request)) return;
            _broadcastState();
            if (_wantsPlay) _startPlaying();
          });
          return;
        } catch (error) {
          if (!_isCurrent(request)) return;
          debugPrint(
              'Unable to load song ${song.id}, attempt $attempt: $error');
        }
      }
      if (!_isCurrent(request)) return;
      if (visited + 1 < count) {
        _curIndex = (_curIndex + (next ? 1 : -1) + count) % count;
      }
      position = Duration.zero;
    }
    if (!_isCurrent(request)) return;
    _loading = false;
    _wantsPlay = false;
    await _player.stop();
    if (!_isCurrent(request)) return;
    _broadcastState(state: AudioProcessingState.error, error: '当前播放列表没有可播放的歌曲');
  }

  void _startPlaying() {
    final request = _request;
    _lastProgress = DateTime.now();
    // just_audio's play future completes on pause/end, not on command receipt.
    // Returning it to MediaSession would leave a control request pending.
    unawaited(_player.play().catchError((Object error) {
      if (_isCurrent(request) && !_loading && _wantsPlay) unawaited(_recover());
    }));
  }

  Future<void> _recover() async {
    if (_recovering ||
        _loading ||
        !_wantsPlay ||
        queue.value.isEmpty ||
        _disposed) return;
    _recovering = true;
    try {
      if (_recoveries++ == 0) {
        await _load(_curIndex, playIt: true, position: _player.position);
      } else {
        await _advance();
      }
    } finally {
      _recovering = false;
    }
  }

  Future<void> _advance({bool next = true, bool completed = false}) async {
    if (queue.value.isEmpty || _disposed) return;
    final repeat =
        completed && _audioServiceRepeatMode == AudioServiceRepeatMode.one;
    final index = repeat
        ? _curIndex
        : (_curIndex + (next ? 1 : -1) + queue.value.length) %
            queue.value.length;
    await playIndex(index);
  }

  @override
  Future<void> pause() async {
    _wantsPlay = false;
    await _player.pause();
    _broadcastState();
  }

  @override
  Future<void> play() async {
    if (_disposed || queue.value.isEmpty) return;
    _wantsPlay = true;
    if (_loading) {
      _broadcastState();
    } else if (!_loaded ||
        _player.processingState == ProcessingState.completed ||
        _player.processingState == ProcessingState.idle) {
      await playIndex(_curIndex);
    } else {
      _startPlaying();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_loaded || _loading) return;
    await _player.seek(position);
    _lastProgress = DateTime.now();
    _broadcastState();
  }

  @override
  Future<void> skipToQueueItem(int index) => playIndex(index);

  @override
  Future<void> skipToNext() => _advance();

  @override
  Future<void> skipToPrevious() => _advance(next: false);

  @override
  Future<void> stop() async {
    ++_request;
    _streamProbe?.close();
    _streamProbe = null;
    qualityReport.value = null;
    _wantsPlay = false;
    _loading = false;
    _loaded = false;
    _sleepTimer?.cancel();
    await _withPlayer(() => _player.stop());
    _broadcastState();
  }

  @override
  Future<void> fastForward() async {
    if (_television) {
      await _seekRelative(const Duration(seconds: 10));
    } else {
      await Home.to.likeSong(liked: true);
    }
  }

  @override
  Future<void> rewind() async {
    if (_television) {
      await _seekRelative(const Duration(seconds: -10));
    } else {
      await Home.to.likeSong(liked: false);
    }
  }

  Future<void> _seekRelative(Duration delta) async {
    final total = mediaItem.value?.duration ?? Duration.zero;
    if (total <= Duration.zero) return;
    final target = (_player.position + delta)
        .inMilliseconds
        .clamp(0, total.inMilliseconds);
    await seek(Duration(milliseconds: target));
  }

  @override
  Future customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'sleep' || name == 'cancelSleep') {
      _sleepTimer?.cancel();
      final seconds = extras?['time'] ?? 0;
      if (name == 'sleep' && seconds > 0) {
        _sleepTimer = Timer(Duration(seconds: seconds), () {
          unawaited(pause());
          Home.to.sleepMinTo = 0;
          Home.to.sleepSlide.value = true;
        });
      }
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    // A reorder cancels the pending generation and reloads the selected song.
    final wasLoading = _loading;
    final wanted = _wantsPlay;
    final selectedId =
        queue.value.isEmpty ? mediaItem.value?.id : queue.value[_curIndex].id;
    _audioServiceRepeatMode = repeatMode;
    final updated = List<MediaItem>.of(_playList);
    if (repeatMode == AudioServiceRepeatMode.none) updated.shuffle();
    final index = updated.indexWhere((e) => e.id == selectedId);
    _curIndex = index < 0 ? 0 : index;
    queue.add(updated);
    final reloading = wasLoading && updated.isNotEmpty
        ? _load(_curIndex, playIt: wanted)
        : Future<void>.value();
    await _box.put(repeatModeSp, repeatMode.name);
    await _box.put(playByIndex, _curIndex);
    _broadcastState();
    await reloading;
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      setRepeatMode(shuffleMode == AudioServiceShuffleMode.none
          ? AudioServiceRepeatMode.all
          : AudioServiceRepeatMode.none);

  Future<void> dispose() async {
    await stop();
    _disposed = true;
    _watchdog?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    qualityReport.dispose();
  }

  @override
  Future<void> onTaskRemoved() async => stop();
}

class MediaItemMessage {
  /// A unique id.
  final String id;

  /// The title of this media item.
  final String title;

  /// The album this media item belongs to.
  final String? album;

  /// The artist of this media item.
  final String? artist;

  /// The genre of this media item.
  final String? genre;

  /// The duration of this media item.
  final Duration? duration;

  /// The artwork for this media item as a uri.
  final Uri? artUri;

  /// Whether this is playable (i.e. not a folder).
  final bool? playable;

  /// Override the default title for display purposes.
  final String? displayTitle;

  /// Override the default subtitle for display purposes.
  final String? displaySubtitle;

  /// Override the default description for display purposes.
  final String? displayDescription;

  /// The rating of the MediaItemMessage.

  /// A map of additional metadata for the media item.
  ///
  /// The values must be integers or strings.
  final Map<String, dynamic>? extras;

  /// Creates a [MediaItemMessage].
  ///
  /// The [id] must be unique for each instance.
  const MediaItemMessage({
    required this.id,
    required this.title,
    this.album,
    this.artist,
    this.genre,
    this.duration,
    this.artUri,
    this.playable = true,
    this.displayTitle,
    this.displaySubtitle,
    this.displayDescription,
    this.extras,
  });

  /// Creates a [MediaItemMessage] from a map of key/value pairs corresponding to
  /// fields of this class.
  factory MediaItemMessage.fromMap(Map<String, dynamic> raw) =>
      MediaItemMessage(
        id: raw['id'] as String,
        title: raw['title'] as String,
        album: raw['album'] as String?,
        artist: raw['artist'] as String?,
        genre: raw['genre'] as String?,
        duration: raw['duration'] != null
            ? Duration(milliseconds: raw['duration'] as int)
            : null,
        artUri:
            raw['artUri'] != null ? Uri.parse(raw['artUri'] as String) : null,
        playable: raw['playable'] as bool?,
        displayTitle: raw['displayTitle'] as String?,
        displaySubtitle: raw['displaySubtitle'] as String?,
        displayDescription: raw['displayDescription'] as String?,
        extras: castMap(raw['extras'] as Map?),
      );

  /// Converts this [MediaItemMessage] to a map of key/value pairs corresponding to
  /// the fields of this class.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'title': title,
        'album': album,
        'artist': artist,
        'genre': genre,
        'duration': duration?.inMilliseconds,
        'artUri': artUri?.toString(),
        'playable': playable,
        'displayTitle': displayTitle,
        'displaySubtitle': displaySubtitle,
        'displayDescription': displayDescription,
        'extras': extras,
      };
}

Map<String, dynamic>? castMap(Map? map) => map?.cast<String, dynamic>();

class StreamSource extends StreamAudioSource {
  String uri;
  String fileType;

  // Get the Android content uri and the corresponsing file type by using MediaStore API in android
  StreamSource(this.uri, this.fileType);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    // Use a method channel to read the file into a List of bytes
    Uint8List fileBytes = Uint8List.fromList(
        (await File(uri).readAsBytes()).map((e) => e ^ 0xa3).toList());

    // Returning the stream audio response with the parameters
    return StreamAudioResponse(
      sourceLength: fileBytes.length,
      contentLength: (end ?? fileBytes.length) - (start ?? 0),
      offset: start ?? 0,
      stream: Stream.fromIterable([fileBytes.sublist(start ?? 0, end)]),
      contentType: fileType == 'flac' ? 'audio/flac' : 'audio/mpeg',
    );
  }
}
