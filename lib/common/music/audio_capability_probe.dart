// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../audio_quality.dart';
import '../audio_quality_preferences.dart';
import '../bujuan_audio_handler.dart';
import '../constants/key.dart';
import 'unified_library.dart';
import '../audio_stream_info.dart';
import '../downloads.dart';
import '../download_availability.dart';
import '../netease_api/src/dio_ext.dart';
import '../netease_api/src/netease_api.dart';
import 'music_source.dart';
import 'qq_music.dart';

/// Explicit diagnostic build only. Complete files stay in temporary app storage;
/// no session, account ID, signed URL, user downloads or preferences are exported.
Future<void> runAudioCapabilityProbe(QqMusic qq, Box box) async {
  void report(String event, Map<String, Object?> row) =>
      debugPrint('BUYU_CAPABILITY $event ${jsonEncode(row)}');
  if (const bool.fromEnvironment('BUYU_DOWNLOAD_OPTIONS_SMOKE')) {
    try {
      final api = NeteaseMusicApi();
      for (final hasHires in [true, false]) {
        final result = await api.searchSong(
            hasHires ? '紫荆花盛开' : 'Someone Like You Adele',
            limit: 5);
        final detail = await Https.dioProxy.postUri(api.songDetailDioMetaData(
            result.result.songs.map((s) => s.id).toList()));
        final raw = ((detail.data as Map)['songs'] as List)
            .whereType<Map>()
            .firstWhere((s) => hasHires
                ? s['hr'] is Map && (s['hr']['size'] as num? ?? 0) > 0
                : s['hr'] == null && s['sq'] is Map);
        final availability = await DownloadAvailability.load(
            MediaItem(id: '${raw['id']}', title: '${raw['name']}'));
        report('download-options', {
          'source': 'netease',
          'title': raw['name'],
          'hasHiresResource': hasHires,
          'offered': availability.allowed?.map((q) => q.name).toList()
        });
      }
      final song = (await qq.search('我好像在哪见过你 薛之谦', limit: 3)).first;
      final availability = await DownloadAvailability.load(song);
      report('download-options', {
        'source': 'qq',
        'title': song.title,
        'offered': availability.allowed?.map((q) => q.name).toList()
      });
    } catch (e) {
      report('fatal', {'errorType': '${e.runtimeType}'});
    }
    report('complete', {'mode': 'download-options'});
    return;
  }
  if (const bool.fromEnvironment('BUYU_CAPABILITY_SMOKE')) {
    await _runCapabilitySmoke(qq, box, report);
    return;
  }
  final seed = DateTime.now().millisecondsSinceEpoch;
  final random = Random(seed);
  final api = NeteaseMusicApi();
  final temp = await Directory(
          '${(await getTemporaryDirectory()).path}/buyu-capability-$seed')
      .create();
  report('start', {'seed': seed, 'qqSignedIn': qq.loggedIn});
  try {
    await qq.refreshProfile();
    report('qq-session', {'valid': true});
    for (final source in MusicSource.values) {
      final queries = [
        '王菲',
        '陈奕迅',
        '林俊杰',
        '邓紫棋',
        '毛不易',
        '李荣浩',
        '赵雷',
        '陈粒',
        'Adele',
        '久石让',
        '邓丽君',
        '孙燕姿'
      ]..shuffle(random);
      final pool = <MediaItem>[];
      final resources = <String, Map>{};
      for (final query in queries.take(5)) {
        try {
          if (source == MusicSource.qq) {
            final songs = await qq.search(query, limit: 6);
            for (final song in songs) {
              pool.add(song);
              resources[song.id] = {
                'hiresBytes': song.extras?['file']?['size_hires'],
                'losslessBytes': song.extras?['file']?['size_flac']
              };
            }
          } else {
            final search = await api.searchSong(query, limit: 6);
            final detail = await Https.dioProxy.postUri(
                api.songDetailDioMetaData(
                    search.result.songs.map((s) => s.id).toList()));
            final body = detail.data as Map;
            for (final song in (body['songs'] as List).whereType<Map>()) {
              final id = '${song['id']}';
              final artists = (song['ar'] as List? ?? [])
                  .whereType<Map>()
                  .map((s) => s['name'])
                  .join(' / ');
              pool.add(
                  MediaItem(id: id, title: '${song['name']}', artist: artists));
              final privileges = (body['privileges'] as List? ?? [])
                  .whereType<Map>()
                  .where((p) => '${p['id']}' == id);
              resources[id] = {
                'hiresBytes': song['hr']?['size'],
                'losslessBytes': song['sq']?['size'],
                if (privileges.isNotEmpty)
                  'playbackMax': privileges.first['playMaxBrLevel'],
                if (privileges.isNotEmpty)
                  'downloadMax': privileges.first['downloadMaxBrLevel']
              };
            }
          }
        } catch (e) {
          report('catalog-error',
              {'source': source.name, 'errorType': '${e.runtimeType}'});
        }
      }
      pool.shuffle(random);
      final samples = <MediaItem>[];
      final artists = <String>{};
      for (final song in pool) {
        if (samples.length < 4 && artists.add(song.artist ?? song.title))
          samples.add(song);
      }
      final controls = pool
          .where((s) => (resources[s.id]?['hiresBytes'] as num? ?? 0) > 0)
          .toList();
      if (controls.isNotEmpty && !samples.any((s) => s.id == controls.first.id))
        samples.add(controls.first);
      report('selection', {
        'source': source.name,
        'poolSize': pool.length,
        'sampleCount': samples.length,
        'hiresResourceCandidates': controls.length
      });
      for (var index = 0; index < samples.length; index++) {
        final song = samples[index];
        report('song', {
          'source': source.name,
          'sample': index,
          'title': song.title,
          'artist': song.artist,
          'selection': index < 4 ? 'random' : 'hires-resource-control',
          ...resources[song.id] ?? {}
        });
        for (final quality in AudioQuality.values.reversed) {
          final row = <String, Object?>{
            'source': source.name,
            'sample': index,
            'title': song.title,
            'requested': quality.name,
            'operation': 'playback',
            'resolved': false,
            'progressed': false
          };
          AudioStreamProbe? probe;
          try {
            String? url;
            if (source == MusicSource.qq) {
              final audio = await qq.audio(song, quality, allowFallback: false);
              url = audio.url;
              row['returned'] = audio.quality.name;
            } else {
              final result =
                  await api.songDownloadUrl([song.id], level: quality.name);
              final items =
                  result.data?.where((s) => s.id == song.id).toList() ?? [];
              if (items.isNotEmpty) {
                url = items.first.url;
                row['returned'] = items.first.level;
                row['trial'] = items.first.freeTrialInfo != null;
              }
            }
            if (url != null && url.isNotEmpty) {
              row['resolved'] = true;
              probe = AudioStreamProbe();
              final info = await probe.inspect(url);
              _recordInfo(row, info);
              row.addAll(await _playProbe(url));
            }
          } catch (e) {
            row['errorType'] = '${e.runtimeType}';
            if (e is HttpException) row['httpError'] = e.message;
          } finally {
            probe?.close();
          }
          report('case', row);

          final downloadRow = <String, Object?>{
            'source': source.name,
            'sample': index,
            'title': song.title,
            'requested': quality.name,
            'operation': 'download',
            'complete': false,
            'offlinePlayed': false
          };
          final service = Downloads(
              allowUnverifiedQuality: true,
              box: _ProbeBox(box),
              directory: () async => temp,
              onStatus: (_) {},
              resolve: (s, q) => Downloads.resolveOfficial(s, q),
              publish: (file, name, item, mime) async {
                final probe = AudioStreamProbe();
                try {
                  _recordInfo(downloadRow, await probe.inspect(file.path));
                } finally {
                  probe.close();
                }
                downloadRow['bytes'] = await file.length();
                downloadRow['offlinePlayed'] =
                    (await _playProbe(file.path))['progressed'];
                return 'probe://complete';
              });
          try {
            await service.add(song, quality: quality);
            await service.idle.timeout(const Duration(seconds: 150));
            final job = service.jobs.single;
            downloadRow.addAll({
              'complete': job.state == DownloadState.complete,
              'returned': job.resolvedQuality,
              'bytes': job.received,
              'actual': job.actual,
              'error': job.error
            });
          } catch (e) {
            downloadRow['errorType'] = '${e.runtimeType}';
          } finally {
            service.dispose();
          }
          report('case', downloadRow);
        }
      }
    }
  } catch (e) {
    report('fatal', {'errorType': '${e.runtimeType}'});
  } finally {
    await temp.delete(recursive: true);
    report('complete', {'done': true});
  }
}

void _recordInfo(Map<String, Object?> row, AudioStreamInfo? info) {
  if (info != null)
    row.addAll({
      'format': info.format,
      'bits': info.bits,
      'sampleRate': info.sampleRate,
      'channels': info.channels,
      'frameBitrate': info.frameBitrate
    });
}

Future<Map<String, Object?>> _playProbe(String path) async {
  final player = AudioPlayer();
  Object? failure;
  final subscription =
      player.playbackEventStream.listen((_) {}, onError: (Object e) {
    failure = e;
  });
  try {
    await player.setVolume(0);
    final duration = await (path.startsWith('http')
            ? player.setUrl(path)
            : player.setFilePath(path))
        .timeout(const Duration(seconds: 15));
    unawaited(player.play().catchError((Object e) {
      failure = e;
    }));
    await Future<void>.delayed(const Duration(seconds: 2));
    return {
      'nativeLoaded': true,
      'durationMs': duration?.inMilliseconds,
      'progressed': failure == null && player.position.inMilliseconds >= 500
    };
  } finally {
    await subscription.cancel();
    await player.dispose();
  }
}

class _ProbeBox implements Box {
  _ProbeBox(this.source);
  final Box source;
  final _data = <dynamic, dynamic>{'DOWNLOAD_JOBS': <dynamic>[]};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => _data.containsKey(key)
      ? _data[key]
      : source.get(key, defaultValue: defaultValue);
  @override
  Future<void> put(dynamic key, dynamic value) async {
    _data[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _runCapabilitySmoke(QqMusic qq, Box box,
    void Function(String, Map<String, Object?>) report) async {
  final temp = await Directory(
          '${(await getTemporaryDirectory()).path}/buyu-capability-smoke-${DateTime.now().millisecondsSinceEpoch}')
      .create();
  final library = UnifiedLibrary(box);
  final keys = [
    AudioQualityPreferences.playbackFallbackKey,
    audioQualitySp,
    'DOWNLOAD_QUALITY',
    for (final s in MusicSource.values)
      for (final use in AudioQualityUse.values)
        AudioQualityPreferences.key(s, use)
  ];
  final before = jsonEncode([for (final key in keys) box.get(key)]);
  try {
    await qq.refreshProfile();
    report('start', {'mode': 'final-smoke', 'qqSessionValid': true});
    for (final source in MusicSource.values) {
      late MediaItem song;
      if (source == MusicSource.qq) {
        final matches = library.songs
            .where((s) => sourceOf(s) == source && s.title.contains('我好像在哪见过你'))
            .toList();
        song = matches.isNotEmpty
            ? matches.first
            : (await qq.search('我好像在哪见过你 薛之谦', limit: 3)).first;
      } else {
        final api = NeteaseMusicApi();
        final search = await api.searchSong('紫荆花盛开', limit: 5);
        final response = await Https.dioProxy.postUri(api.songDetailDioMetaData(
            search.result.songs.map((s) => s.id).toList()));
        final songs =
            ((response.data as Map)['songs'] as List).whereType<Map>().toList();
        final raw =
            songs.firstWhere((s) => s['hr'] is Map, orElse: () => songs.first);
        song = MediaItem(id: '${raw['id']}', title: '${raw['name']}');
      }
      final memory = _ProbeBox(box);
      if (const bool.fromEnvironment('BUYU_STRICT_QUALITY_SMOKE'))
        memory._data[AudioQualityPreferences.playbackFallbackKey] = false;
      memory._data[audioQualitySp] = 'hires';
      memory._data['DOWNLOAD_QUALITY'] = 'hires';
      for (final use in AudioQualityUse.values)
        memory._data[AudioQualityPreferences.key(source, use)] = 'hires';
      report('policy', {
        'source': source.name,
        'playback':
            AudioQualityOptions.supported(source, AudioQualityUse.playback)
                .map((q) => q.name)
                .toList(),
        'download':
            AudioQualityOptions.supported(source, AudioQualityUse.download)
                .map((q) => q.name)
                .toList()
      });
      final availability = await DownloadAvailability.load(song);
      report('download-options', {
        'source': source.name,
        'title': song.title,
        'hasHiresResource': source == MusicSource.netease,
        'offered': availability.allowed?.map((q) => q.name).toList()
      });
      final player = AudioPlayer();
      await player.setVolume(0);
      final handler =
          BujuanAudioHandler(player: player, box: memory, restoreQueue: false);
      try {
        handler.queue.add([song]);
        await handler.playIndex(0).timeout(const Duration(seconds: 45));
        final until = DateTime.now().add(const Duration(seconds: 8));
        while (DateTime.now().isBefore(until) &&
            !(player.playing && player.position.inMilliseconds >= 1000)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        final value = handler.qualityReport.value;
        report('case', {
          'source': source.name,
          'operation': 'playback',
          'title': song.title,
          'fallbackEnabled':
              AudioQualityPreferences(memory).playbackFallbackEnabled,
          'requested': value?.requested.name,
          'returned': value?.returnedLevel,
          'bits': value?.stream?.bits,
          'sampleRate': value?.stream?.sampleRate,
          'progressed': player.playing && player.position.inMilliseconds >= 1000
        });
      } finally {
        await handler.dispose();
      }
      final row = <String, Object?>{
        'source': source.name,
        'operation': 'download',
        'title': song.title
      };
      final downloads = Downloads(
          box: memory,
          directory: () async => temp,
          onStatus: (_) {},
          resolve: (song, quality) async {
            try {
              return await Downloads.resolveOfficial(song, quality);
            } catch (e) {
              row['resolverErrorType'] = '${e.runtimeType}';
              if (e is DioException) {
                row['httpStatus'] = e.response?.statusCode;
                row['transportType'] = e.type.name;
                row['endpoint'] =
                    e.requestOptions.uri.host + e.requestOptions.uri.path;
              }
              rethrow;
            }
          },
          publish: (file, _, __, ___) async {
            final probe = AudioStreamProbe();
            try {
              _recordInfo(row, await probe.inspect(file.path));
            } finally {
              probe.close();
            }
            row['offlinePlayed'] = (await _playProbe(file.path))['progressed'];
            return 'probe://complete';
          });
      try {
        await downloads.add(song);
        await downloads.idle.timeout(const Duration(seconds: 150));
        final job = downloads.jobs.single;
        row.addAll({
          'requested': job.quality.name,
          'returned': job.resolvedQuality,
          'complete': job.state == DownloadState.complete,
          'bytes': job.received,
          'error': job.error
        });
      } finally {
        downloads.dispose();
      }
      report('case', row);
    }
    if (const bool.fromEnvironment('BUYU_STRICT_QUALITY_SMOKE')) {
      final api = NeteaseMusicApi();
      final search = await api.searchSong('Someone Like You Adele', limit: 5);
      final detail = await Https.dioProxy.postUri(api.songDetailDioMetaData(
          search.result.songs.map((s) => s.id).toList()));
      final songs =
          ((detail.data as Map)['songs'] as List).whereType<Map>().toList();
      final raw = songs.firstWhere((s) => s['hr'] == null && s['sq'] is Map);
      final song = MediaItem(id: '${raw['id']}', title: '${raw['name']}');
      final availability = await DownloadAvailability.load(song);
      report('download-options', {
        'source': 'netease',
        'title': song.title,
        'hasHiresResource': false,
        'offered': availability.allowed?.map((q) => q.name).toList()
      });
      final requested = <String>[];
      final spy = InterceptorsWrapper(onRequest: (options, handler) {
        final data = options.data;
        if (data is Map &&
            data['level'] != null &&
            (data['id'] == '${raw['id']}' ||
                '${data['ids']}'.contains('${raw['id']}')))
          requested.add('${data['level']}');
        handler.next(options);
      });
      Https.dio.interceptors.insert(0, spy);
      final memory = _ProbeBox(box);
      memory._data[AudioQualityPreferences.playbackFallbackKey] = false;
      for (final use in AudioQualityUse.values)
        memory._data[AudioQualityPreferences.key(MusicSource.netease, use)] =
            'hires';
      try {
        final player = AudioPlayer();
        await player.setVolume(0);
        final handler = BujuanAudioHandler(
            player: player, box: memory, restoreQueue: false);
        try {
          handler.queue.add([song]);
          await handler.playIndex(0).timeout(const Duration(seconds: 45));
          report('strict-failure', {
            'operation': 'playback',
            'source': 'netease',
            'title': song.title,
            'stopped': !player.playing,
            'error': handler.playbackState.value.errorMessage,
            'requests': List<String>.of(requested)
          });
        } finally {
          await handler.dispose();
        }
        requested.clear();
        var published = false;
        final downloads = Downloads(
            box: memory,
            directory: () async => temp,
            onStatus: (_) {},
            publish: (_, __, ___, ____) async {
              published = true;
              return 'probe://unexpected';
            });
        try {
          await downloads.add(song);
          await downloads.idle.timeout(const Duration(seconds: 60));
          report('strict-failure', {
            'operation': 'download',
            'source': 'netease',
            'title': song.title,
            'failed': downloads.jobs.single.state == DownloadState.failed,
            'published': published,
            'error': downloads.jobs.single.error,
            'requests': List<String>.of(requested)
          });
        } finally {
          downloads.dispose();
        }
      } finally {
        Https.dio.interceptors.remove(spy);
      }
    }
  } catch (e) {
    report('fatal', {'errorType': '${e.runtimeType}'});
  } finally {
    library.dispose();
    await temp.delete(recursive: true);
    report('complete', {
      'done': true,
      'preferencesUnchanged':
          before == jsonEncode([for (final key in keys) box.get(key)])
    });
  }
}
