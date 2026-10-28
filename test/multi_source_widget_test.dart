// Community maintenance and new features: tiancaiProgramer.
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/music/mixed_search.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/unified_library.dart';
import 'package:bujuan/pages/music/mixed_library_view.dart';
import 'package:bujuan/pages/music/mixed_search_view.dart';
import 'package:bujuan/pages/play_list/playlist_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'multi_source_test.dart' show Remote, neSong, qqSong;

Widget frame(Widget child, Size size) => ScreenUtilInit(
    designSize:
        size.width > size.height ? const Size(750, 346) : const Size(750, 1334),
    builder: (_, __) =>
        MaterialApp(theme: AppTheme.light, home: Scaffold(body: child)));

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
        'combined search filters providers without another query at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      final search = MixedSearch(providers: {
        MusicSource.netease: (_, __) async {
          calls++;
          return [neSong];
        },
        MusicSource.qq: (_, __) async {
          calls++;
          return [qqSong];
        },
      });
      await tester.pumpWidget(
          frame(MixedSongSearchView(query: '同名歌曲', search: search), size));
      await tester.pumpAndSettle();
      expect(find.byType(SongItem), findsNWidgets(2));
      expect(find.text(' · 网易云'), findsOneWidget);
      expect(find.text(' · QQ音乐'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'QQ音乐'));
      await tester.pumpAndSettle();
      expect(tester.widget<SongItem>(find.byType(SongItem)).mediaItem.id,
          'qq:abc');
      expect(calls, 2);
      await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
      await tester.pumpAndSettle();
      expect(find.byType(SongItem), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      search.dispose();
    });
  }

  testWidgets(
      'local collection uses both sources and keeps QQ-only actions isolated',
      (tester) async {
    const size = Size(844, 390);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final a = Remote()..account = '', b = Remote()..account = '';
    final box = MemoryBox();
    GetIt.I.registerSingleton<Box>(box);
    final library = UnifiedLibrary(box,
        remotes: {MusicSource.netease: a, MusicSource.qq: b});
    GetIt.I.registerSingleton<UnifiedLibrary>(library);
    addTearDown(() async {
      library.dispose();
      await GetIt.I.reset();
    });
    await library.setFavorite(neSong, true);
    await library.setFavorite(qqSong, true);
    await library.sync();
    await tester.pumpWidget(frame(const MixedLibraryView(), size));
    await tester.pumpAndSettle();
    expect(find.byType(SongItem), findsNWidgets(2));
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        3);
    expect(find.textContaining('2 项等待同步'), findsOneWidget);
    final qqRow = find
        .byWidgetPredicate((w) => w is SongItem && w.mediaItem.id == 'qq:abc');
    await tester
        .tap(find.descendant(of: qqRow, matching: find.byType(IconButton)));
    await tester.pumpAndSettle();
    expect(find.text('取消聚合收藏'), findsOneWidget);
    expect(find.text('下载歌曲'), findsOneWidget);
    expect(find.text('查看歌曲评论'), findsOneWidget);
    expect(find.text('收藏到QQ歌单'), findsOneWidget);
    expect(find.text('加入本地文件夹'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
