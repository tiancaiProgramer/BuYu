// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pointycastle/digests/md5.dart';
import 'audio_quality.dart';
import 'audio_stream_info.dart';
import 'netease_api/src/dio_ext.dart';
import 'netease_api/src/netease_handler.dart';

class DownloadSource {
  const DownloadSource(this.url, {this.size, this.md5, this.level});
  final String url;
  final int? size;
  final String? md5, level;
}

enum DownloadState { queued, downloading, saving, complete, failed, cancelled }

class DownloadJob {
  DownloadJob(this.song, this.quality);
  final MediaItem song;
  final AudioQuality quality;
  String get key => '${song.id}:${quality.name}';
  DownloadState state = DownloadState.queued;
  int received = 0, total = 0;
  String? uri, error, filename, actual;
  CancelToken token = CancelToken();
  bool get active => [
        DownloadState.queued,
        DownloadState.downloading,
        DownloadState.saving
      ].contains(state);
  String get status => switch (state) {
        DownloadState.queued => '等待下载',
        DownloadState.downloading => total > 0
            ? '下载中 ${(received * 100 / total).clamp(0, 100).toStringAsFixed(0)}%'
            : '下载中 ${(received / 1048576).toStringAsFixed(1)} MB',
        DownloadState.saving => '正在保存',
        DownloadState.complete => '已下载 · ${actual ?? quality.label}',
        DownloadState.failed => error ?? '下载失败，点重试',
        DownloadState.cancelled => '已取消',
      };
  MediaItem get localSong => MediaItem(
          id: 'download:$key',
          title: song.title,
          artist: song.artist,
          album: song.album,
          duration: song.duration,
          artUri: song.artUri,
          extras: {
            'type': 'local',
            'url': uri,
            'image': song.extras?['image'] ?? ''
          });
  Map<String, dynamic> toMap() => {
        'id': song.id,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'duration': song.duration?.inMilliseconds,
        'image': song.extras?['image'],
        'quality': quality.name,
        'state': state.name,
        'uri': uri,
        'filename': filename,
        'actual': actual,
        'received': received,
        'total': total
      };
  static DownloadJob fromMap(Map map) {
    final job = DownloadJob(
        MediaItem(
            id: map['id'] as String,
            title: map['title'] as String,
            artist: map['artist'] as String?,
            album: map['album'] as String?,
            duration: map['duration'] == null
                ? null
                : Duration(milliseconds: map['duration'] as int),
            extras: {'image': map['image']}),
        AudioQuality.parse(map['quality']));
    job.state = DownloadState.values.firstWhere((s) => s.name == map['state'],
        orElse: () => DownloadState.failed);
    job.uri = map['uri'] as String?;
    job.filename = map['filename'] as String?;
    job.actual = map['actual'] as String?;
    job.received = map['received'] as int? ?? 0;
    job.total = map['total'] as int? ?? 0;
    if (job.active) {
      job.state = DownloadState.failed;
      job.error = '下载中断，点重试';
    }
    return job;
  }
}

class Downloads extends ChangeNotifier {
  Downloads(
      {required this.box,
      Future<Directory> Function()? directory,
      Future<DownloadSource> Function(MediaItem, AudioQuality)? resolve,
      Future<String> Function(File, String, MediaItem, String)? publish,
      Dio? dio,
      void Function(DownloadJob)? onStatus})
      : _directory = directory ??
            (() async => Directory(
                '${(await getTemporaryDirectory()).path}/bujuan-downloads')),
        _resolve = resolve == null
            ? ((song, quality, token) =>
                resolveOfficial(song, quality, cancelToken: token))
            : ((song, quality, token) => resolve(song, quality)),
        _publish = publish ??
            ((file, name, song, mime) => publishAudio(file, name, song, mime,
                tree: box.get('DOWNLOAD_FOLDER_URI') as String?)),
        _onStatus = onStatus ?? _nativeStatus,
        _dio = dio ?? Dio() {
    for (final raw
        in box.get('DOWNLOAD_JOBS', defaultValue: <dynamic>[]) as List) {
      try {
        jobs.add(DownloadJob.fromMap(Map.from(raw as Map)));
      } catch (_) {}
    }
  }
  static const qualityKey = 'DOWNLOAD_QUALITY';
  static const folderKey = 'DOWNLOAD_FOLDER_URI';
  static const folderNameKey = 'DOWNLOAD_FOLDER_NAME';
  AudioQuality get defaultQuality =>
      AudioQuality.parse(box.get(qualityKey, defaultValue: 'exhigh'));
  String get folderLabel =>
      box.get(folderNameKey, defaultValue: 'Music/BuJuan') as String;
  void settingsChanged() => _notify();

  static Downloads get instance {
    final services = GetIt.instance;
    if (!services.isRegistered<Downloads>())
      services.registerSingleton<Downloads>(Downloads(box: services<Box>()),
          dispose: (s) => s.dispose());
    return services<Downloads>();
  }

  final Box box;
  final List<DownloadJob> jobs = [];
  final Future<Directory> Function() _directory;
  final Future<DownloadSource> Function(MediaItem, AudioQuality, CancelToken)
      _resolve;
  final Future<String> Function(File, String, MediaItem, String) _publish;
  final Dio _dio;
  final void Function(DownloadJob) _onStatus;
  final Map<String, String> _lastStatuses = {};
  DateTime _lastProgress = DateTime(2000);
  static void _nativeStatus(DownloadJob job) {
    if (!Platform.isAndroid) return;
    unawaited(channel.invokeMethod<void>('downloadStatus', {
      'key': job.key,
      'title': job.song.title,
      'state': job.state.name,
      'status': job.status,
      'received': job.received,
      'total': job.total,
    }).catchError((_) {}));
  }

  static Future<bool> prepareNotifications() async {
    if (!Platform.isAndroid) return true;
    try {
      return (await Permission.notification.request()).isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void>? _running;
  bool _disposed = false;
  Future<void> get idle => _running ?? Future.value();
  void _notify() {
    if (_disposed) return;
    notifyListeners();
    final now = DateTime.now();
    for (final job in jobs) {
      final changed = _lastStatuses[job.key] != job.state.name;
      final progress = job.state == DownloadState.downloading &&
          now.difference(_lastProgress).inMilliseconds >= 1000;
      if (!changed && !progress) continue;
      // Restored history is not a newly completed download.
      if (_lastStatuses[job.key] == null && !job.active) {
        _lastStatuses[job.key] = job.state.name;
        continue;
      }
      _lastStatuses[job.key] = job.state.name;
      if (progress) _lastProgress = now;
      _onStatus(job);
    }
  }

  Future<void> _persist() async {
    if (!_disposed)
      await box.put('DOWNLOAD_JOBS', jobs.map((j) => j.toMap()).toList());
  }

  static Future<DownloadSource> resolveOfficial(
      MediaItem song, AudioQuality preferred,
      {CancelToken? cancelToken}) async {
    for (final quality in preferred.fallbacks) {
      final metadata = DioMetaData(
          Uri.parse(
              'https://interface.music.163.com/eapi/song/enhance/download/url/v1'),
          data: {'id': song.id, 'level': quality.name, 'immerseType': 'c51'},
          options: joinOptions(
              encryptType: EncryptType.EApi,
              eApiUrl: '/api/song/enhance/download/url/v1'));
      final response = await Https.dioProxy
          .postUri(metadata, cancelToken: cancelToken)
          .timeout(const Duration(seconds: 15));
      final body = response.data;
      if (body is! Map || body['code'] != 200 || body['data'] is! Map) continue;
      final item = body['data'] as Map;
      if (item['freeTrialInfo'] != null) continue;
      final url = item['url'];
      if (url is String &&
          url.isNotEmpty &&
          ['http', 'https'].contains(Uri.tryParse(url)?.scheme)) {
        return DownloadSource(url,
            size: item['size'] as int?,
            md5: item['md5'] as String?,
            level: item['level'] as String?);
      }
    }
    throw StateError('当前歌曲或账号暂无可用下载资源');
  }

  static const channel = MethodChannel('bujuan/downloads');
  static Future<String> publishAudio(
      File file, String name, MediaItem song, String mime,
      {String? tree}) async {
    if (Platform.isAndroid) {
      final sdk = await channel.invokeMethod<int>('sdk') ?? 29;
      if (tree == null &&
          sdk < 29 &&
          !await Permission.storage.request().isGranted)
        throw StateError('未授予音乐保存权限');
      final result =
          await channel.invokeMapMethod<String, dynamic>('saveAudio', {
        'source': file.path,
        'name': name,
        'title': song.title,
        'artist': song.artist ?? '',
        'album': song.album ?? '',
        'tree': tree,
        'mime': mime
      });
      if (result?['uri'] is String) return result!['uri'] as String;
      throw StateError('音乐保存失败');
    }
    final root = await getApplicationDocumentsDirectory();
    final output = Directory('${root.path}/BuJuan');
    await output.create(recursive: true);
    return (await file.copy('${output.path}/$name')).path;
  }

  DownloadJob? forSong(MediaItem song, {AudioQuality? quality}) {
    quality ??= defaultQuality;
    for (final job in jobs) {
      if (job.song.id == song.id && job.quality == quality) return job;
    }
    return null;
  }

  Future<void> add(MediaItem song, {AudioQuality? quality}) async {
    quality ??= defaultQuality;
    if (song.extras?['type'] == 'local' || (int.tryParse(song.id) ?? 0) <= 0)
      throw StateError('本地歌曲无需下载');
    var job = forSong(song, quality: quality);
    if (job?.active == true || job?.state == DownloadState.complete) return;
    if (job == null) {
      job = DownloadJob(song, quality);
      jobs.insert(0, job);
    }
    job.state = DownloadState.queued;
    job.error = null;
    job.received = 0;
    job.total = 0;
    job.token = CancelToken();
    await _persist();
    _notify();
    _running ??= Future<void>.microtask(_drain);
  }

  void cancel(DownloadJob job) {
    if (job.state == DownloadState.saving || !job.active) return;
    job.state = DownloadState.cancelled;
    job.token.cancel();
    _notify();
    unawaited(_persist());
  }

  Future<void> _drain() async {
    try {
      while (!_disposed) {
        final queued =
            jobs.where((j) => j.state == DownloadState.queued).toList();
        if (queued.isEmpty) break;
        await _download(queued.first);
      }
    } finally {
      _running = null;
    }
  }

  static String safeName(String title) {
    final safe = title.replaceAll(RegExp(r'[\x00-\x1f/\\:*?"<>|]'), '_').trim();
    return String.fromCharCodes(safe.runes.take(40));
  }

  Future<void> _download(DownloadJob job) async {
    File? temporary;
    try {
      job.state = DownloadState.downloading;
      _notify();
      await _persist();
      final source = await _resolve(job.song, job.quality, job.token);
      if (job.token.isCancelled) throw StateError('cancelled');
      final directory = await _directory();
      await directory.create(recursive: true);
      temporary = File('${directory.path}/${safeName(job.key)}.part');
      var last = DateTime(2000);
      await _dio.download(source.url, temporary.path,
          cancelToken: job.token,
          options: Options(
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Accept-Encoding': 'identity'}),
          onReceiveProgress: (received, total) {
        job.received = received;
        job.total = total > 0 ? total : source.size ?? 0;
        if (DateTime.now().difference(last).inMilliseconds >= 120) {
          last = DateTime.now();
          _notify();
        }
      });
      if (job.token.isCancelled) throw StateError('cancelled');
      final size = await temporary.length();
      if (size == 0 ||
          source.size != null && source.size! > 0 && size != source.size)
        throw StateError('文件不完整，请重试');
      if (source.md5 != null &&
          RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(source.md5!)) {
        final digest = MD5Digest();
        await for (final chunk in temporary.openRead()) {
          if (job.token.isCancelled) throw StateError('cancelled');
          digest.update(Uint8List.fromList(chunk), 0, chunk.length);
        }
        final bytes = Uint8List(digest.digestSize);
        digest.doFinal(bytes, 0);
        if (bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join() !=
            source.md5!.toLowerCase()) throw StateError('文件校验失败，请重试');
      }
      final handle = await temporary.open();
      late List<int> prefix;
      try {
        prefix = await handle.read(65536);
        final skip = AudioStreamInfo.id3Length(prefix);
        if (skip >= prefix.length && skip < size) {
          await handle.setPosition(skip);
          prefix = await handle.read(65536);
        }
      } finally {
        await handle.close();
      }
      final info = AudioStreamInfo.parse(prefix);
      if (info == null) throw StateError('下载内容不是支持的音频文件');
      if (job.token.isCancelled) throw StateError('cancelled');
      final extension = info.format == 'FLAC' ? 'flac' : 'mp3';
      final name =
          '${safeName('${job.song.title} - ${job.song.artist ?? ''}')} [${safeName(job.song.id)}_${job.quality.name}].$extension';
      job.state = DownloadState.saving;
      _notify();
      job.uri = await _publish(temporary, name, job.song,
          extension == 'flac' ? 'audio/flac' : 'audio/mpeg');
      job.filename = name;
      job.actual = info.description;
      job.state = DownloadState.complete;
      job.received = size;
      job.total = size;
      await _persist();
      debugPrint(
          'BuJuan download completed: ${job.song.id}, ${info.description}, $size bytes');
    } catch (error) {
      if (job.token.isCancelled) {
        job.state = DownloadState.cancelled;
      } else {
        job.state = DownloadState.failed;
        job.error =
            error is StateError ? error.message.toString() : '下载失败，请检查网络后重试';
      }
      await _persist();
    } finally {
      try {
        if (temporary != null && await temporary.exists())
          await temporary.delete();
      } on FileSystemException {
        /* A removed staging file must not block the queue. */
      }
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final job in jobs) {
      job.token.cancel();
    }
    _dio.close(force: true);
    super.dispose();
  }
}
