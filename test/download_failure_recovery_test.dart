// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/downloads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'audio_stream_info_test.dart' show flacHeader;

void main() {
  late Directory root;
  late Box box;
  late HttpServer server;
  const song = MediaItem(id: '100001', title: '下载恢复测试');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('buyu-download-recovery');
    Hive.init(root.path);
    box = await Hive.openBox('recovery');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
    await box.close();
    await root.delete(recursive: true);
  });

  for (final failure in {'permission denied': 13, 'disk full': 28}.entries) {
    test('${failure.key} cannot report success and retry survives restart',
        () async {
      server.listen((request) async {
        request.response.add(flacHeader());
        await request.response.close();
      });
      var failSaving = true;
      var successfulSaves = 0;
      Downloads create() => Downloads(
          box: box,
          directory: () async => Directory('${root.path}/staging'),
          resolve: (_, __) async => DownloadSource(
              'http://127.0.0.1:${server.port}/audio',
              size: flacHeader().length),
          publish: (file, _, __, ___) async {
            if (failSaving) {
              throw FileSystemException(
                  failure.key, file.path, OSError(failure.key, failure.value));
            }
            successfulSaves++;
            return (await file.copy('${root.path}/saved.flac')).uri.toString();
          });
      var downloads = create();
      try {
        await downloads.add(song);
        await downloads.idle;
        expect(downloads.jobs.single.state, DownloadState.failed);
        expect(downloads.jobs.single.uri, isNull);
        expect(successfulSaves, 0);
        expect(
            await Directory('${root.path}/staging').list().toList(), isEmpty);
        await box.flush();
        downloads.dispose();
        downloads = create();
        expect(downloads.jobs.single.state, DownloadState.failed);
        failSaving = false;
        await downloads.add(song);
        await downloads.idle;
        expect(downloads.jobs, hasLength(1));
        expect(downloads.jobs.single.state, DownloadState.complete);
        expect(downloads.jobs.single.attempts, 2);
        expect(successfulSaves, 1);
        expect(
            await File('${root.path}/saved.flac').readAsBytes(), flacHeader());
        expect(
            await Directory('${root.path}/staging').list().toList(), isEmpty);
      } finally {
        downloads.dispose();
      }
    });
  }

  test(
      'failed transfer can retry without duplicate jobs or partial publication',
      () async {
    var available = false;
    var requests = 0, saves = 0;
    server.listen((request) async {
      requests++;
      if (available) {
        request.response.add(flacHeader());
      } else {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      }
      await request.response.close();
    });
    final downloads = Downloads(
        box: box,
        directory: () async => Directory('${root.path}/staging'),
        resolve: (_, __) async => DownloadSource(
            'http://127.0.0.1:${server.port}/audio',
            size: flacHeader().length),
        publish: (_, __, ___, ____) async {
          saves++;
          return 'content://test/saved-audio';
        });
    try {
      await Future.wait(List.generate(4, (_) => downloads.add(song)));
      await downloads.idle;
      expect(downloads.jobs, hasLength(1));
      expect(downloads.jobs.single.state, DownloadState.failed);
      expect((requests, saves), (1, 0));
      expect(await Directory('${root.path}/staging').list().toList(), isEmpty);
      available = true;
      await Future.wait(List.generate(4, (_) => downloads.add(song)));
      await downloads.idle;
      expect(downloads.jobs, hasLength(1));
      expect(downloads.jobs.single.state, DownloadState.complete);
      expect(downloads.jobs.single.attempts, 2);
      expect((requests, saves), (2, 1));
      expect(await Directory('${root.path}/staging').list().toList(), isEmpty);
    } finally {
      downloads.dispose();
    }
  });
}
