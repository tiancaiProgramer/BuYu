// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import '../../common/audio_stream_info.dart';

class QqCacheScan {
  QqCacheScan();
  final songs = <MediaItem>[];
  int encryptedOrUnknown = 0, inaccessible = 0, visited = 0;
  bool truncated = false;
}

/// Read existing ordinary audio only; never rename, decrypt or change files.
Future<QqCacheScan> scanQqCache(List<String> directories,
    {int maxFiles = 2000}) async {
  final result = QqCacheScan(), seen = <String>{};
  Future<void> scan(Directory directory, int depth) async {
    if (depth > 4 || result.truncated) return;
    try {
      if (!await directory.exists()) {
        result.inaccessible++;
        return;
      }
      await for (final entity in directory.list(followLinks: false)) {
        if (result.visited >= maxFiles) {
          result.truncated = true;
          break;
        }
        if (entity is Directory) {
          await scan(entity, depth + 1);
          continue;
        }
        if (entity is! File || !seen.add(entity.path)) continue;
        result.visited++;
        try {
          final file = await entity.open();
          List<int> bytes;
          try {
            bytes = await file.read(64 * 1024);
          } finally {
            await file.close();
          }
          final info = AudioStreamInfo.parse(bytes);
          bool magic(int at, String s) =>
              bytes.length >= at + s.length &&
              List.generate(s.length, (i) => bytes[at + i]).join(',') ==
                  s.codeUnits.join(',');
          final plain = info != null ||
              magic(0, 'OggS') ||
              magic(0, 'RIFF') && magic(8, 'WAVE') ||
              magic(4, 'ftyp');
          if (!plain) {
            result.encryptedOrUnknown++;
            continue;
          }
          final name = entity.uri.pathSegments.last;
          result.songs.add(MediaItem(
              id: entity.uri.toString(),
              title: name,
              artist: 'QQ音乐本地文件',
              extras: {
                'type': 'local',
                'source': 'qq',
                'url': entity.path,
                'cacheFormat': info?.description ?? '普通音频',
              }));
        } on FileSystemException {
          result.inaccessible++;
        }
      }
    } on FileSystemException {
      result.inaccessible++;
    }
  }

  for (final directory in directories) {
    await scan(Directory(directory), 0);
  }
  return result;
}
