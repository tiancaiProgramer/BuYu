// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../audio_quality.dart';
import '../bujuan_audio_handler.dart';
import '../audio_stream_info.dart';
import '../constants/key.dart';
import '../netease_api/src/netease_api.dart';
import 'music_source.dart';
import 'qq_music.dart';
import 'unified_library.dart';

/// Explicit development build only. Logs no sessions, account IDs or signed URLs.
/// Uses an independent muted player and never writes favorites or playback prefs.
Future<void> runAudioQualityProbe(QqMusic qq, Box box) async {
  void report(String name, Map<String, Object?> data) =>
      debugPrint('BUYU_AUDIO_QUALITY $name ${jsonEncode(data)}');
  final library = UnifiedLibrary(box);
  final api = NeteaseMusicApi();
  final trace = InterceptorsWrapper(onRequest: (options, handler) {
    if (const bool.fromEnvironment('BUYU_QQ_MODERN_VKEY')) {
      final body = options.data;
      final rpc = body is Map ? body['req_0'] : null;
      if (rpc is Map && rpc['method'] == 'CgiGetVkey') {
        rpc['module'] = 'music.vkey.GetVkey';
        rpc['method'] = 'UrlGetVkey';
      }
    }
    handler.next(options);
  }, onResponse: (response, handler) {
    try {
      final request = response.requestOptions.data as Map;
      final rpc = request['req_0'] as Map;
      if (['CgiGetVkey', 'UrlGetVkey'].contains(rpc['method'])) {
        final raw = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final part = raw is Map ? raw['req_0'] : null;
        final data = part is Map ? part['data'] : null;
        final entries = data is Map ? data['midurlinfo'] : null;
        final item =
            entries is List && entries.isNotEmpty && entries.first is Map
                ? entries.first as Map
                : null;
        final purl = '${item?['purl'] ?? ''}';
        final uri = Uri.tryParse(purl);
        final file = uri?.pathSegments.lastOrNull ?? '';
        final requested = '${rpc['param']['filename'][0]}';
        report('qq-response', {
          'method': rpc['method'],
          'requestedPrefix': requested.substring(0, 4),
          'code': raw is Map ? raw['code'] : null,
          'rpcCode': part is Map ? part['code'] : null,
          'dataCode': data is Map ? data['code'] : null,
          'result': item?['result'],
          'purlEmpty': purl.isEmpty,
          'returnedPrefix': file.length >= 4 ? file.substring(0, 4) : file,
          'returnedExtension': file.contains('.') ? file.split('.').last : null,
          'sipHosts': data is Map && data['sip'] is List
              ? (data['sip'] as List)
                  .whereType<String>()
                  .map((s) => Uri.tryParse(s)?.host)
                  .toList()
              : []
        });
      }
    } catch (_) {
      report('qq-response', {'parseFailed': true});
    }
    handler.next(response);
  }, onError: (error, handler) {
    report('qq-transport',
        {'type': error.type.name, 'status': error.response?.statusCode});
    handler.next(error);
  });
  qq.client.interceptors.add(trace);
  report('sessions', {
    'qq': qq.loggedIn,
    'neteaseCached': (box.get(loginData) ?? '').toString().isNotEmpty,
    'favorites': library.songs.length
  });
  try {
    try {
      await qq.refreshProfile();
      report('qq-session-check', {'profileValid': true});
    } catch (e) {
      report('qq-session-check', {
        'profileValid': false,
        'error': e is MusicServiceError ? e.message : '${e.runtimeType}'
      });
    }
    for (final source in MusicSource.values) {
      const only = String.fromEnvironment('BUYU_AUDIO_QUALITY_SOURCE');
      if (only.isNotEmpty && source.name != only) continue;
      final selected = box.get(playById);
      final current = <MediaItem>[];
      for (final raw in box.get(playQueue, defaultValue: <String>[]) as List) {
        try {
          final data = jsonDecode(raw as String) as Map;
          if (data['id'] == selected)
            current.add(MediaItem(
                id: data['id'] as String,
                title: data['title'] as String,
                extras: data['extras'] is Map
                    ? Map<String, dynamic>.from(data['extras'])
                    : null));
        } catch (_) {/* Older queue metadata is optional. */}
      }
      final samples = <String, MediaItem>{
        for (final song in [...current, ...library.songs]
            .where((s) => sourceOf(s) == source))
          song.id: song
      };
      for (final query in ['海阔天空', '晴天', '我好像在哪见过你']) {
        if (samples.length >= 4) break;
        try {
          if (source == MusicSource.qq) {
            for (final song in await qq.search(query, limit: 2)) {
              if (samples.length < 4) samples.putIfAbsent(song.id, () => song);
            }
          } else {
            final result = await api.searchSong(query, limit: 2);
            for (final song in result.result.songs) {
              if (samples.length < 4)
                samples.putIfAbsent(song.id,
                    () => MediaItem(id: song.id, title: song.name ?? query));
            }
          }
        } catch (e) {
          report('catalog',
              {'source': source.name, 'errorType': '${e.runtimeType}'});
        }
      }
      for (final song in samples.values.take(4)) {
        for (final quality in AudioQuality.values.reversed) {
          final result = <String, Object?>{
            'source': source.name,
            'song': song.title,
            'requested': quality.name,
            'urlAvailable': false,
            'nativeLoaded': false,
            'progressed': false
          };
          AudioStreamProbe? probe;
          final player = AudioPlayer();
          Object? playbackError;
          final errors =
              player.playbackEventStream.listen((_) {}, onError: (Object e) {
            playbackError = e;
          });
          try {
            await player.setVolume(0);
            String? url;
            if (source == MusicSource.qq) {
              final audio = await qq.audio(song, quality, allowFallback: false);
              url = audio.url;
              result.addAll(
                  {'returned': audio.quality.name, 'type': audio.format});
            } else {
              final response = await api.songDownloadUrl([song.id],
                  level: quality.name).timeout(const Duration(seconds: 12));
              final items =
                  response.data?.where((s) => s.id == song.id).toList() ?? [];
              if (items.isNotEmpty) {
                final item = items.first;
                url = item.url;
                result.addAll({
                  'returned': item.level,
                  'type': item.type,
                  'bitrate': item.br,
                  'size': item.size,
                  'trial': item.freeTrialInfo != null,
                  'code': item.code
                });
              }
            }
            if (url != null && url.isNotEmpty) {
              result['urlAvailable'] = true;
              probe = AudioStreamProbe();
              try {
                final info = await probe.inspect(url);
                if (info != null)
                  result.addAll({
                    'headerFormat': info.format,
                    'sampleRate': info.sampleRate,
                    'bits': info.bits,
                    'channels': info.channels,
                    'frameBitrate': info.frameBitrate
                  });
              } catch (e) {
                result['headerErrorType'] = '${e.runtimeType}';
                if (e is HttpException) result['headerError'] = e.message;
              }
              playbackError = null;
              final duration =
                  await player.setUrl(url).timeout(const Duration(seconds: 12));
              result['nativeLoaded'] = true;
              result['durationMs'] = duration?.inMilliseconds;
              unawaited(player.play().catchError((Object e) {
                playbackError = e;
              }));
              await Future<void>.delayed(const Duration(seconds: 2));
              result['progressed'] = player.position.inMilliseconds >= 500 &&
                  playbackError == null;
              if (playbackError != null)
                result['playErrorType'] = '${playbackError.runtimeType}';
              if (playbackError is PlatformException)
                result['playErrorCode'] =
                    (playbackError as PlatformException).code;
            }
          } catch (e) {
            result['errorType'] = '${e.runtimeType}';
            if (e is PlayerException) result['nativeErrorCode'] = e.code;
          } finally {
            probe?.close();
            await errors.cancel();
            await player.dispose();
          }
          report('sample', result);
        }
      }
      if (source == MusicSource.qq && samples.isNotEmpty) {
        final song = samples.values.first;
        final player = AudioPlayer();
        await player.setVolume(0);
        final originalPreference = box.get(audioQualitySp);
        final handler = BujuanAudioHandler(
            player: player, box: _QualityProbeBox(box), restoreQueue: false);
        try {
          handler.queue.add([song]);
          await handler.playIndex(0).timeout(const Duration(seconds: 45));
          final until = DateTime.now().add(const Duration(seconds: 15));
          while (DateTime.now().isBefore(until) &&
              !(player.playing && player.position.inMilliseconds >= 1000)) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          report('automatic-fallback', {
            'song': song.title,
            'requested': handler.qualityReport.value?.requested.name,
            'returned': handler.qualityReport.value?.returnedLevel,
            'progressed':
                player.playing && player.position.inMilliseconds >= 1000,
            'sameSong': handler.mediaItem.value?.id == song.id,
            'preferenceUnchanged': box.get(audioQualitySp) == originalPreference
          });
        } catch (e) {
          report('automatic-fallback', {'errorType': '${e.runtimeType}'});
        } finally {
          await handler.dispose();
        }
      }
    }
  } catch (e) {
    report('fatal', {'errorType': '${e.runtimeType}'});
  } finally {
    qq.client.interceptors.remove(trace);
    library.dispose();
    report('complete', {'done': true});
  }
}

// Delegate reads and intercept writes; the diagnostic handler cannot persist its queue or quality.
class _QualityProbeBox implements Box {
  _QualityProbeBox(this.source);
  final Box source;
  final _overrides = <dynamic, dynamic>{audioQualitySp: AudioQuality.hires.name};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => _overrides.containsKey(key)
      ? _overrides[key]
      : source.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _overrides[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
