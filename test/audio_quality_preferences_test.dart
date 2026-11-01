// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/audio_quality_preferences.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/downloads.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/pages/setting/platform_audio_quality_sheet.dart';
import 'package:bujuan/widget/download_song_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'playback_regression_test.dart' show FakePlayer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('playback and download expose only verified platform tiers', () {
    for (final use in AudioQualityUse.values) {
      expect(AudioQualityOptions.supported(MusicSource.qq, use),
          [AudioQuality.standard, AudioQuality.exhigh, AudioQuality.lossless]);
      expect(AudioQualityOptions.supported(MusicSource.netease, use),
          AudioQuality.values);
      expect(AudioQualityOptions.clamp(MusicSource.qq, use, AudioQuality.hires),
          AudioQuality.lossless);
    }
  });
  test(
      'playback fallback defaults on and persists independently of quality/download settings',
      () async {
    final box = MemoryBox();
    final prefs = AudioQualityPreferences(box);
    expect(prefs.playbackFallbackEnabled, isTrue);
    await prefs.setPlaybackFallback(false);
    expect(AudioQualityPreferences(box).playbackFallbackEnabled, isFalse);
    expect(box.get('DOWNLOAD_QUALITY'), isNull);
    expect(prefs.get(MusicSource.netease, AudioQualityUse.playback),
        AudioQuality.exhigh);
    await prefs.setPlaybackFallback(true);
    expect(prefs.playbackFallbackEnabled, isTrue);
  });
  test('legacy preferences are read without modifying shared values', () async {
    final box = MemoryBox();
    await box.put(audioQualitySp, 'hires');
    await box.put(Downloads.qualityKey, 'higher');
    final prefs = AudioQualityPreferences(box);
    expect(prefs.get(MusicSource.netease, AudioQualityUse.playback),
        AudioQuality.hires);
    expect(prefs.get(MusicSource.qq, AudioQualityUse.download),
        AudioQuality.standard);
    expect(box.data.length, 2);
  });
  test(
      'platform and playback/download choices remain independent across reopen',
      () async {
    final box = MemoryBox();
    final prefs = AudioQualityPreferences(box);
    await prefs.set(
        MusicSource.netease, AudioQualityUse.playback, AudioQuality.hires);
    await prefs.set(
        MusicSource.qq, AudioQualityUse.playback, AudioQuality.standard);
    await prefs.set(
        MusicSource.qq, AudioQualityUse.download, AudioQuality.lossless);
    final reopened = AudioQualityPreferences(box);
    expect(reopened.get(MusicSource.netease, AudioQualityUse.playback),
        AudioQuality.hires);
    expect(reopened.get(MusicSource.qq, AudioQualityUse.playback),
        AudioQuality.standard);
    expect(reopened.get(MusicSource.qq, AudioQualityUse.download),
        AudioQuality.lossless);
    expect(reopened.get(MusicSource.netease, AudioQualityUse.download),
        AudioQuality.exhigh);
    expect(box.get(audioQualitySp), isNull);
    expect(box.get(Downloads.qualityKey), isNull);
  });
  test('editing another platform does not interrupt current playback',
      () async {
    final box = MemoryBox();
    final player = FakePlayer();
    final handler = BujuanAudioHandler(
        player: player,
        box: box,
        restoreQueue: false,
        urlResolver: (_) async => 'https://example.test/audio.mp3');
    try {
      await handler.changeQueueLists([
        const MediaItem(id: 'qq:a', title: 'QQ', extras: {'source': 'qq'})
      ]);
      await handler.setAudioQuality(AudioQuality.hires,
          source: MusicSource.netease);
      expect(player.loadedUrls.length, 1);
      await handler.setAudioQuality(AudioQuality.standard,
          source: MusicSource.qq);
      expect(player.loadedUrls.length, 2);
      expect(handler.qualityReport.value?.requested, AudioQuality.standard);
    } finally {
      await handler.dispose();
    }
  });
  testWidgets('quality sheet switches platform without committing a selection',
      (tester) async {
    final box = MemoryBox();
    final prefs = AudioQualityPreferences(box);
    (MusicSource, AudioQuality)? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlatformAudioQualitySheet(
                use: AudioQualityUse.playback,
                preferences: prefs,
                onSelected: (s, q) {
                  selected = (s, q);
                }))));
    expect(find.text('Hi-Res'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quality-source:qq')));
    await tester.pumpAndSettle();
    expect(find.text('较高'), findsNothing);
    expect(find.text('Hi-Res'), findsNothing);
    expect(selected, isNull);
    expect(box.data, isEmpty);
    await tester.tap(find.byKey(const ValueKey('audio-quality:lossless')));
    expect(selected, (MusicSource.qq, AudioQuality.lossless));
  });
  testWidgets(
      'QQ download picker requires retry when resource lookup fails',
      (tester) async {
    final box = MemoryBox();
    GetIt.I.registerSingleton<Box>(box);
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DownloadQualityPicker(
                  song: const MediaItem(
                      id: 'qq:a', title: 'QQ', extras: {'source': 'qq'}),
                  loader: (_) async => throw StateError('Offline')))));
      await tester.pumpAndSettle();
      expect(find.text('较高'), findsNothing);
      expect(find.text('Hi-Res'), findsNothing);
      expect(find.text('无损'), findsNothing);
      expect(find.text('资源信息读取失败，点击重试'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.I.reset();
    }
  });
}
