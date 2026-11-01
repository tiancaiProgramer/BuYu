// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:dio/dio.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
  test('QQ resource metadata cannot reintroduce globally unsupported tiers',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, response) {
      response.resolve(Response(requestOptions: options, data: {
        'code': 0,
        'req_0': {
          'code': 0,
          'data': {
            'track_info': {
              'mid': 'abc',
              'file': {
                'size_hires': 90000000,
                'size_flac': 40000000,
                'size_128mp3': 3000000,
                'size_320mp3': 8000000
              }
            }
          }
        }
      }));
    }));
    final qq = QqMusic(dio: dio);
    GetIt.I.registerSingleton<QqMusic>(qq);
    try {
      final available = await DownloadAvailability.load(const MediaItem(
          id: 'qq:abc', title: 'QQ', extras: {'source': 'qq', 'mid': 'abc'}));
      expect(available.allowed,
          {AudioQuality.standard, AudioQuality.exhigh, AudioQuality.lossless});
    } finally {
      qq.dispose();
      await GetIt.I.reset();
    }
  });

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
    expect(available.allowed, {AudioQuality.standard, AudioQuality.exhigh});
    expect(available.labels[AudioQuality.standard], contains('128 kbps'));
    expect(available.labels[AudioQuality.hires], '当前账号或歌曲暂不提供');
  });
  for (final hr in [
    null,
    <String, dynamic>{},
    {'size': 0},
    {'size': 70000000}
  ]) {
    test('Hi-Res download requires a listed positive resource: $hr', () {
      final available = DownloadAvailability.parse({
        'songs': [
          {
            'id': 1,
            'l': {'size': 3000000},
            'sq': {'size': 40000000},
            'hr': hr
          }
        ],
        'privileges': [
          {'id': 1, 'dl': 999000, 'downloadMaxBrLevel': 'hires'}
        ]
      }, '1');
      expect(available.allowed!.contains(AudioQuality.hires),
          hr != null && (hr['size'] as num? ?? 0) > 0);
      expect(available.allowed, contains(AudioQuality.lossless));
    });
  }
  test('resources remain required when account ceiling is unspecified', () {
    final available = DownloadAvailability.parse({
      'songs': [
        {
          'id': 1,
          'sq': {'size': 40000000}
        }
      ]
    }, '1');
    expect(available.allowed, {AudioQuality.lossless});
  });
  testWidgets(
      'download picker hides absent tiers and does not offer unverified tiers',
      (tester) async {
    GetIt.I.registerSingleton<Box>(MemoryBox());
    final pending = Completer<DownloadAvailability>();
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DownloadQualityPicker(
                song: const MediaItem(id: '1', title: '测试'),
                loader: (_) {
                  attempts++;
                  if (attempts == 1) return pending.future;
                  return Future.value(
                      const DownloadAvailability({}, {AudioQuality.lossless}));
                }))));
    expect(find.text('Hi-Res'), findsNothing);
    expect(find.byType(RadioListTile<AudioQuality>), findsNothing);
    pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Hi-Res'), findsNothing);
    await tester.tap(find.text('资源信息读取失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('Hi-Res'), findsNothing);
    expect(find.text('无损'), findsOneWidget);
    expect(find.byType(RadioListTile<AudioQuality>), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.I.reset();
  });
  testWidgets('download picker offers Hi-Res only when available',
      (tester) async {
    GetIt.I.registerSingleton<Box>(MemoryBox());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DownloadQualityPicker(
                song: const MediaItem(id: '1', title: '测试'),
                loader: (_) async =>
                    const DownloadAvailability({}, {AudioQuality.hires})))));
    await tester.pumpAndSettle();
    expect(find.text('Hi-Res'), findsOneWidget);
    expect(find.text('无损'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.I.reset();
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
