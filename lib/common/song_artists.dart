import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'netease_api/src/api/play/bean.dart';

class SongArtists {
  static List<Artists> fromSong(MediaItem song) {
    final result = <Artists>[];
    final raw = song.extras?['artist'];
    try {
      final value = raw is String
          ? jsonDecode(raw.trim().startsWith('[')
              ? raw
              : '[${raw.replaceAll(RegExp(r'}\s*/\s*{'), '},{')}]')
          : raw;
      for (final entry in value is List ? value : const []) {
        if (entry is Map) {
          final artist = Artists.fromJson(Map<String, dynamic>.from(entry));
          if ((artist.name ?? '').trim().isNotEmpty &&
              !result.any((a) => a.id == artist.id && a.name == artist.name))
            result.add(artist);
        }
      }
    } catch (_) {/* Older queues may only contain display names. */}
    if (result.isEmpty) {
      result.addAll((song.artist ?? '')
          .split(' / ')
          .where((name) => name.trim().isNotEmpty)
          .map((name) => Artists()
            ..id = ''
            ..name = name.trim()));
    }
    return result;
  }
}
