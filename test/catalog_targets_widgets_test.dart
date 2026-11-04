// Community maintenance and new features: tiancaiProgramer.
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/common/music/catalog_search.dart';
import 'package:bujuan/common/music/mixed_search.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/unified_library.dart';
import 'package:bujuan/pages/music/catalog_search_view.dart';
import 'package:bujuan/pages/music/favorite_targets_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'favorite_targets_test.dart' show TargetRemote;
import 'multi_source_test.dart' show qqSong;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() async => GetIt.I.reset());
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    void screen(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets(
        'catalog isolates source failure, retries and opens source identity at $size',
        (t) async {
      screen(t);
      var fail = true;
      MediaItem? opened;
      final item = CatalogSearch.qqItem(
          CatalogKind.album, {'albumMID': 'qq-album', 'albumName': 'QQ专辑'});
      final search = MixedSearch(providers: {
        MusicSource.netease: (_, __) async => [
              CatalogSearch.neteaseItem(
                  CatalogKind.album, {'id': 1, 'name': '网易专辑'})
            ],
        MusicSource.qq: (_, __) async {
          if (fail) throw StateError('offline');
          return [item];
        }
      });
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
              body: CatalogSearchView(
                  query: 'test',
                  kind: CatalogKind.album,
                  search: search,
                  onOpen: (s) => opened = s))));
      await t.pumpAndSettle();
      expect(find.text('网易专辑'), findsOneWidget);
      expect(find.textContaining('QQ音乐暂不可用'), findsOneWidget);
      fail = false;
      await t.tap(find.textContaining('QQ音乐暂不可用'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, 'QQ音乐'));
      await t.pumpAndSettle();
      expect(find.text('网易专辑'), findsNothing);
      await t.tap(find.text('QQ专辑'));
      expect(opened?.extras!['catalogId'], 'qq-album');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      search.dispose();
    });
    testWidgets(
        'target confirmation cancel then merge retains destination and theme at $size',
        (t) async {
      screen(t);
      final box = MemoryBox();
      // Both remotes and the library must share the same account-scoped target storage.
      final source = TargetRemote(box, MusicSource.qq);
      source.cloud['auto'] = [qqSong];
      final ne = TargetRemote(box, MusicSource.netease);
      ne.account = '';
      final library = UnifiedLibrary(box,
          remotes: {MusicSource.qq: source, MusicSource.netease: ne});
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.dark, home: FavoriteTargetsView(library: library)));
      await t.tap(find.byKey(const ValueKey('favorite-target:qq')));
      await t.pumpAndSettle();
      await t.tap(find.text('新歌单'));
      await t.pumpAndSettle();
      expect(find.text('合并当前收藏？'), findsOneWidget);
      await t.tap(find.text('取消'));
      await t.pumpAndSettle();
      expect(library.targets.get(MusicSource.qq, 'user'), isNull);
      await t.tap(find.byKey(const ValueKey('favorite-target:qq')));
      await t.pumpAndSettle();
      await t.tap(find.text('新歌单'));
      await t.pumpAndSettle();
      await t.tap(find.text('合并并连接'));
      await t.pumpAndSettle();
      expect(library.targets.get(MusicSource.qq, 'user')?.id, 'new');
      expect(source.cloud['new'], [qqSong]);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      library.dispose();
    });
  }
}
