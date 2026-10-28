// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';

enum MusicSource {
  netease('网易云'),
  qq('QQ音乐');

  const MusicSource(this.label);
  final String label;
}

MusicSource sourceOf(MediaItem song) =>
    song.id.startsWith('qq:') || song.extras?['source'] == 'qq'
        ? MusicSource.qq
        : MusicSource.netease;
bool isLocalSong(MediaItem song) =>
    ['local', 'neteaseCache'].contains(song.extras?['type']);
String sourceKey(MediaItem song) =>
    '${sourceOf(song).name}:${song.id.replaceFirst(RegExp(r'^qq:'), '')}';
String sourceSubtitle(MediaItem song) =>
    '${song.artist ?? ''} · ${sourceOf(song).label}';
Map<String, dynamic> saveSong(MediaItem song) => {
      'id': song.id,
      'title': song.title,
      'artist': song.artist,
      'album': song.album,
      'duration': song.duration?.inMilliseconds,
      'art': song.artUri?.toString(),
      'extras': song.extras,
    };
MediaItem restoreSong(Map raw) => MediaItem(
    id: raw['id'] as String,
    title: raw['title'] as String,
    artist: raw['artist'] as String?,
    album: raw['album'] as String?,
    artUri: Uri.tryParse(raw['art'] as String? ?? ''),
    duration: raw['duration'] == null
        ? null
        : Duration(milliseconds: raw['duration'] as int),
    extras:
        raw['extras'] is Map ? Map<String, dynamic>.from(raw['extras']) : null);

class SourcePlaylist {
  const SourcePlaylist(
      {required this.source,
      required this.id,
      required this.name,
      this.image = '',
      this.count = 0,
      this.directory = ''});
  final MusicSource source;
  final String id, name, image, directory;
  final int count;
}

class MusicServiceError implements Exception {
  const MusicServiceError(this.message);
  final String message;
  @override
  String toString() => message;
}
