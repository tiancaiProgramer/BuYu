import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/downloads.dart';
import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'audio_stream_info_test.dart' show flacHeader;

void main() {
  late Directory root;
  late Box box;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bujuan-download-test');
    Hive.init(root.path);
    box = await Hive.openBox('downloads');
  });
  tearDown(() async {
    await box.close();
    await root.delete(recursive: true);
  });
  const song = MediaItem(id: '123', title: '测试/歌曲', artist: '歌手');

  test('download publishes only a complete validated file and survives restart',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bytes = flacHeader();
    var hits = 0, publishes = 0;
    final statuses = <DownloadState>[];
    server.listen((request) async {
      hits++;
      request.response.add(bytes);
      await request.response.close();
    });
    await box.put(audioQualitySp, 'standard');
    await box.put(Downloads.qualityKey, 'lossless');
    final service = Downloads(
        box: box,
        onStatus: (job) => statuses.add(job.state),
        directory: () async => Directory('${root.path}/staging'),
        resolve: (_, quality) async => DownloadSource(
            'http://127.0.0.1:${server.port}/signed?token=keep',
            size: bytes.length),
        publish: (file, name, item, mime) async {
          publishes++;
          expect(statuses.last, DownloadState.saving);
          expect(await file.readAsBytes(), bytes);
          expect(name, isNot(contains('/')));
          expect(name, endsWith('.flac'));
          expect(mime, 'audio/flac');
          return (await file.copy('${root.path}/finished.flac')).uri.toString();
        });
    try {
      await service.add(song);
      await service.idle;
      final job = service.jobs.single;
      expect(job.state, DownloadState.complete);
      expect(job.actual, contains('24 bit'));
      expect(
          statuses,
          containsAllInOrder([
            DownloadState.queued,
            DownloadState.downloading,
            DownloadState.saving,
            DownloadState.complete
          ]));
      expect(job.quality, AudioQuality.lossless);
      expect(box.get(audioQualitySp), 'standard');
      expect(job.localSong.extras!['url'], job.uri);
      expect(job.localSong.extras!['type'], 'local');
      expect(await Directory('${root.path}/staging').list().toList(), isEmpty);
      final completedNotifications =
          statuses.where((state) => state == DownloadState.complete).length;
      await service.add(song);
      await service.idle;
      expect(statuses.where((state) => state == DownloadState.complete).length,
          completedNotifications);
      expect((hits, publishes), (1, 1));
      await service.add(song, quality: AudioQuality.hires);
      await service.idle;
      expect(service.jobs.first.quality, AudioQuality.hires);
      expect(service.jobs.length, 2);
      final restored = Downloads(box: box);
      expect(restored.jobs.first.state, DownloadState.complete);
      expect(restored.jobs.first.uri, job.uri);
      restored.dispose();
    } finally {
      service.dispose();
      await server.close(force: true);
    }
  });

  test('corrupt size cannot publish an incomplete download', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add(flacHeader());
      await request.response.close();
    });
    var published = false;
    final service = Downloads(
        box: box,
        directory: () async => Directory('${root.path}/staging'),
        resolve: (_, __) async => DownloadSource(
            'http://127.0.0.1:${server.port}/audio',
            size: 100000),
        publish: (_, __, ___, ____) async {
          published = true;
          return 'bad';
        });
    try {
      await service.add(song);
      await service.idle;
      expect(service.jobs.single.state, DownloadState.failed);
      expect(service.jobs.single.error, contains('不完整'));
      expect(published, isFalse);
      expect(await Directory('${root.path}/staging').list().toList(), isEmpty);
    } finally {
      service.dispose();
      await server.close(force: true);
    }
  });

  test('cancel while resolving leaves no published file', () async {
    final wait = Completer<DownloadSource>();
    final service = Downloads(
        box: box,
        directory: () async => root,
        resolve: (_, __) => wait.future,
        publish: (_, __, ___, ____) async =>
            throw StateError('must not publish'));
    await service.add(song);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    service.cancel(service.jobs.single);
    wait.complete(const DownloadSource('http://127.0.0.1/no-request'));
    await service.idle;
    await box.flush();
    expect(service.jobs.single.state, DownloadState.cancelled);
    service.dispose();
  });

  test(
      'interrupted persisted jobs are retryable and local songs are not downloaded',
      () async {
    final job = DownloadJob(song, AudioQuality.exhigh)
      ..state = DownloadState.downloading;
    await box.put('DOWNLOAD_JOBS', [job.toMap()]);
    final service = Downloads(box: box);
    expect(service.jobs.single.state, DownloadState.failed);
    expect(service.jobs.single.status, contains('中断'));
    expect(
        () => service.add(const MediaItem(
            id: 'local', title: '本地', extras: {'type': 'local'})),
        throwsStateError);
    service.dispose();
  });
}
