// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/downloads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'audio_stream_info_test.dart' show flacHeader;

void main() {
  late Directory root;
  late Box box;
  late HttpServer server;
  const song = MediaItem(id: '123', title: 'quality download');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('buyu-download-quality-');
    Hive.init(root.path);
    box = await Hive.openBox('quality');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await server.close(force: true);
    await box.close();
    await root.delete(recursive: true);
  });
  for (final strict in [false, true]) {
    test(
        'bad high quality URL ${strict ? 'stops exact diagnostics' : 'fails without lowering quality'}',
        () async {
      final requests = <String>[];
      var saved = 0;
      final bytes = flacHeader(rate: 44100, bits: 16);
      server.listen((request) async {
        if (request.uri.path == '/hires')
          request.response.statusCode = 404;
        else
          request.response.add(bytes);
        await request.response.close();
      });
      final downloads = Downloads(
          box: box,
          allowUnverifiedQuality: strict,
          directory: () async => root,
          resolve: (_, q) async {
            requests.add(q.name);
            return DownloadSource('http://127.0.0.1:${server.port}/${q.name}',
                size: bytes.length, level: q.name);
          },
          publish: (file, _, __, ___) async {
            saved++;
            expect(await file.readAsBytes(), bytes);
            return 'content://test/valid';
          });
      try {
        await downloads.add(song, quality: AudioQuality.hires);
        await downloads.idle;
        final job = downloads.jobs.single;
        expect(requests, ['hires']);
        expect(saved, 0);
        expect(job.state, DownloadState.failed);

        expect(
            root
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.part')),
            isEmpty);
      } finally {
        downloads.dispose();
      }
    });
  }
  test('save failure cannot trigger another network transfer or lower quality',
      () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.add(flacHeader());
      await request.response.close();
    });
    final downloads = Downloads(
        box: box,
        directory: () async => root,
        resolve: (_, q) async => DownloadSource(
            'http://127.0.0.1:${server.port}/file',
            level: q.name),
        publish: (_, __, ___, ____) async =>
            throw const FileSystemException('permission denied'));
    try {
      await downloads.add(song, quality: AudioQuality.lossless);
      await downloads.idle;
      expect(requests, 1);
      expect(downloads.jobs.single.state, DownloadState.failed);
      expect(downloads.jobs.single.uri, isNull);
    } finally {
      downloads.dispose();
    }
  });
}
