// Community maintenance and new features: tiancaiProgramer.
import 'package:hive_flutter/hive_flutter.dart';
import 'audio_quality.dart';
import 'constants/key.dart';
import 'music/music_source.dart';

enum AudioQualityUse { playback, download }

class AudioQualityOptions {
  static List<AudioQuality> supported(
          MusicSource source, AudioQualityUse use) =>
      source == MusicSource.qq
          ? const [
              AudioQuality.standard,
              AudioQuality.exhigh,
              AudioQuality.lossless
            ]
          : AudioQuality.values;

  static AudioQuality clamp(
      MusicSource source, AudioQualityUse use, AudioQuality value) {
    final options = supported(source, use);
    return options.lastWhere((q) => q.index <= value.index,
        orElse: () => options.first);
  }
}

class AudioQualityPreferences {
  AudioQualityPreferences(this.box);
  final Box box;
  static const playbackFallbackKey = 'PLAYBACK_QUALITY_FALLBACK';
  bool get playbackFallbackEnabled =>
      box.get(playbackFallbackKey, defaultValue: true) != false;
  Future<void> setPlaybackFallback(bool enabled) =>
      box.put(playbackFallbackKey, enabled);
  static String key(MusicSource source, AudioQualityUse use) =>
      '${use == AudioQualityUse.playback ? audioQualitySp : 'DOWNLOAD_QUALITY'}.${source.name}';

  AudioQuality get(MusicSource source, AudioQualityUse use) {
    final legacy =
        use == AudioQualityUse.playback ? audioQualitySp : 'DOWNLOAD_QUALITY';
    return AudioQualityOptions.clamp(
        source,
        use,
        AudioQuality.parse(box.get(key(source, use),
            defaultValue: box.get(legacy, defaultValue: 'exhigh'))));
  }

  Future<void> set(
          MusicSource source, AudioQualityUse use, AudioQuality value) =>
      box.put(
          key(source, use), AudioQualityOptions.clamp(source, use, value).name);

  String description(AudioQualityUse use) => MusicSource.values
      .map((source) => '${source.label}：${get(source, use).label}')
      .join(' / ');
}
