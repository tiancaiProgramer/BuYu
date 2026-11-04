// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'package:bujuan/common/music/catalog_search.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:flutter_test/flutter_test.dart';

class _Network extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('official QQ playlist, album and artist searches open real tracks',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final qq = QqMusic();
      try {
        for (final kind in CatalogKind.values) {
          final entities = await CatalogSearch.qq(qq, kind, '周杰伦', 1);
          expect(entities, isNotEmpty, reason: kind.name);
          final tracks = await CatalogSearch.qqSongs(qq, entities.first, 1);
          expect(tracks, isNotEmpty, reason: '${kind.name} tracks');
          expect(
              tracks.every((s) =>
                  sourceOf(s) == MusicSource.qq && s.extras?['mid'] != null),
              true);
        }
        expect(qq.loggedIn, false);
      } finally {
        qq.dispose();
      }
    }, _Network());
  },
      skip: !const bool.fromEnvironment('BUYU_QQ_LIVE'),
      timeout: const Timeout(Duration(seconds: 90)));
}
