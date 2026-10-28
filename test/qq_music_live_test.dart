// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/music/qq_library_api.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfficialNetwork extends HttpOverrides {}

// Explicit read-only network smoke check. Never uses a real account or mutates playlists.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('QQ official search returns metadata through the Dart adapter',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final qq = QqMusic();
      try {
        final songs = await qq.search('晴天', limit: 5);
        expect(songs, isNotEmpty);
        expect(songs.every((s) => sourceOf(s) == MusicSource.qq), isTrue);
        expect(
            songs.every((s) => s.title.isNotEmpty && s.extras?['mid'] != null),
            isTrue);
        expect(qq.loggedIn, isFalse);
        final hot = await qq.songComments(songs.first);
        expect(hot.comments, isNotEmpty);
        expect(hot.comments.first['Content'], isA<String>());
        final fresh = await qq.songComments(songs.first, hot:false);
        expect(fresh.comments, isNotEmpty);
      } finally {
        qq.dispose();
      }
    }, _OfficialNetwork());
  },
      skip: !const bool.fromEnvironment('BUYU_QQ_LIVE'),
      timeout: const Timeout(Duration(seconds: 30)));
}
