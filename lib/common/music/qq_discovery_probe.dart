// Community maintenance and new features: tiancaiProgramer.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../audio_quality.dart';
import 'qq_discovery.dart';
import 'qq_music.dart';
import 'music_source.dart';

/// Read-only development check, absent unless explicitly enabled at build time.
/// Never logs a cookie, user ID, recommendation ID, or signed audio URL.
Future<void> runQqDiscoveryProbe(QqMusic qq) async {
  void report(String name, Map<String, Object?> value) =>
      debugPrint('BUYU_DISCOVERY_PROBE $name ${jsonEncode(value)}');
  if (!qq.loggedIn) {
    report('account', {'loggedIn': false});
    return;
  }
  final service = QqDiscovery(qq);
  try {
    final songs = await service.dailySongs();
    report('daily', {'count': songs.length});
  } catch (e) {
    report('daily',
        {'error': e is MusicServiceError ? e.message : '${e.runtimeType}'});
  }
  try {
    final songs = await service.radioSongs();
    report('radio', {'count': songs.length});
  } catch (e) {
    report('radio',
        {'error': e is MusicServiceError ? e.message : '${e.runtimeType}'});
  }
  try {
    final shows = await service.podcasts(query: '随机波动');
    report('podcasts', {'count': shows.length});
    if (shows.isNotEmpty) {
      final episodes = await service.podcastEpisodes(shows.first);
      report('episodes', {
        'count': episodes.length,
        'longForm': episodes.any((e) => (e.duration?.inMinutes ?? 0) > 20)
      });
      if (episodes.isNotEmpty) {
        final audio = await qq.audio(episodes.first, AudioQuality.standard);
        report('podcast-audio',
            {'resolved': Uri.parse(audio.url).isAbsolute, 'quality': audio.quality.name});
      }
    }
    final catalog = await service.podcasts();
    report('podcast-catalog', {'count': catalog.length});
  } catch (e) {
    report('podcasts',
        {'error': e is MusicServiceError ? e.message : '${e.runtimeType}'});
  }
}
