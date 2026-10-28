// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/downloads.dart';
import 'package:bujuan/pages/downloads/downloads_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'download_preferences_test.dart' show MemoryBox;

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(640, 300)
  ]) {
    testWidgets('download history and record details remain reachable at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final downloads = Downloads(box: MemoryBox(), onStatus: (_) {});
      downloads.jobs.add(DownloadJob(
          const MediaItem(
              id: 'qq:abc',
              title: '稻香',
              artist: '周杰伦',
              extras: {'source': 'qq', 'mid': 'abc'}),
          AudioQuality.exhigh)
        ..state = DownloadState.complete
        ..actual = 'MP3 · 44.1 kHz · 2 声道 · 帧码率 320 kbps'
        ..resolvedQuality = 'exhigh'
        ..received = 8941053
        ..savedFolder = 'Music/BuYuPreview');
      GetIt.I
          .registerSingleton<Downloads>(downloads, dispose: (d) => d.dispose());
      addTearDown(GetIt.I.reset);
      await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light, home: const DownloadsView()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下载记录信息'));
      await tester.pumpAndSettle();
      expect(find.text('请求音质：极高'), findsOneWidget);
      await tester.ensureVisible(find.text('保存文件夹：Music/BuYuPreview'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
