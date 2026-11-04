// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'package:bujuan/pages/local/qq_cache_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'plain audio is recognized by bytes, encrypted/renamed non-audio rejected, files unchanged and overlaps deduplicated',
      () async {
    final d = await Directory.systemTemp.createTemp('buyu-cache-');
    try {
      final plain = File('${d.path}/readable.cache');
      await plain.writeAsBytes([
        ...'RIFF'.codeUnits,
        0,
        0,
        0,
        0,
        ...'WAVE'.codeUnits,
        ...List.filled(64, 0)
      ]);
      final encrypted = File('${d.path}/encrypted.mp3');
      await encrypted.writeAsBytes(List.filled(128, 77));
      final result = await scanQqCache([d.path, d.path, '${d.path}/missing']);
      expect(result.songs.length, 1);
      expect(result.songs.single.extras!['type'], 'local');
      expect(result.songs.single.extras!['url'], plain.path);
      expect(result.encryptedOrUnknown, 1);
      expect(result.inaccessible, 1);
      expect(await encrypted.readAsBytes(), List.filled(128, 77));
      expect(await plain.exists(), true);
      final capped = await scanQqCache([d.path], maxFiles: 1);
      expect(capped.truncated, true);
    } finally {
      await d.delete(recursive: true);
    }
  });
}
