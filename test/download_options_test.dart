import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/download_availability.dart';
import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/downloads.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/widget/download_song_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;

void main() {
  test('official resource sizes and account download ceiling are kept distinct',
      () {
    final available = DownloadAvailability.parse({
      'songs': [
        {
          'id': 1,
          'l': {'br': 128000, 'size': 3000000},
          'h': {'br': 320000, 'size': 8000000},
          'hr': {'br': 3000000, 'size': 70000000}
        }
      ],
      'privileges': [
        {'id': 1, 'dl': 320000, 'downloadMaxBrLevel': 'exhigh'}
      ]
    }, '1');
    expect(available.allowed,
        {AudioQuality.standard, AudioQuality.higher, AudioQuality.exhigh});
    expect(available.labels[AudioQuality.standard], contains('128 kbps'));
    expect(available.labels[AudioQuality.hires], '当前账号或歌曲暂不提供');
  });
  testWidgets('tapping the default download quality submits that quality',
      (tester) async {
    final box = MemoryBox();
    await box.put(Downloads.qualityKey, 'exhigh');
    GetIt.instance.registerSingleton<Box>(box);
    AudioQuality? result;
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    child: const Text('下载'),
                    onPressed: () async {
                      result = await showModalBottomSheet<AudioQuality>(
                          context: context,
                          isScrollControlled: true,
                          builder: (_) => DownloadQualityPicker(
                              song: const MediaItem(id: '1', title: '测试'),
                              loader: (_) async =>
                                  const DownloadAvailability({}, null)));
                    })))));
    await tester.tap(find.text('下载'));
    await tester.pumpAndSettle();
    final selected = tester.widget<RadioListTile<AudioQuality>>(
        find.widgetWithText(RadioListTile<AudioQuality>, '极高'));
    expect(selected.groupValue, AudioQuality.exhigh);
    await tester.tap(find.text('极高'));
    await tester.pumpAndSettle();
    expect(result, AudioQuality.exhigh);
    expect(find.text('选择下载音质'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.instance.reset();
  });
  for (final dark in [false, true]) {
    testWidgets(
        'download labels stay readable inside the coloured player theme: $dark',
        (tester) async {
      final resources = await tester.runAsync(() async {
        final dir =
            await Directory.systemTemp.createTemp('bujuan-download-sheet');
        Hive.init(dir.path);
        return (dir, await Hive.openBox('options'));
      });
      final (dir, box) = resources!;
      GetIt.instance.registerSingleton<Box>(box);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final original = dark ? AppTheme.dark : AppTheme.light;
      await tester.pumpWidget(MaterialApp(
          theme: original.copyWith(
              primaryColor: Colors.white,
              textTheme: original.textTheme.apply(bodyColor: Colors.white)),
          home: Scaffold(
              body: DownloadQualityPicker(
                  song: const MediaItem(id: '1', title: '测试'),
                  loader: (_) async => const DownloadAvailability({}, null)))));
      await tester.pumpAndSettle();
      final element = tester.element(find.text('标准'));
      final foreground = DefaultTextStyle.of(element).style.color!;
      final background = Theme.of(element).scaffoldBackgroundColor;
      final a = foreground.computeLuminance(),
          b = background.computeLuminance();
      expect(
          ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05), greaterThan(4.5));
      expect(find.text('Hi-Res'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.instance.reset();
      await tester.runAsync(() async {
        await box.close();
        await dir.delete(recursive: true);
      });
    });
  }
}
