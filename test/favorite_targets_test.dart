// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/music/favorite_targets.dart';
import 'package:bujuan/common/music/unified_library.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'multi_source_test.dart' show qqSong, neSong;

class TargetRemote
    implements
        FavoritesRemote,
        FavoritesSnapshotReader,
        FavoritesTargetProvider {
  TargetRemote(this.box, this.source);
  final MemoryBox box;
  final MusicSource source;
  @override
  String account = 'user';
  final cloud = <String, List<MediaItem>>{'auto': [], 'new': []};
  final writes = <(String, String, bool)>[];
  Completer<void>? wait;
  bool failRead = false;
  @override
  Future<List<SourcePlaylist>> targetOptions() async =>
      [SourcePlaylist(source: source, id: 'new', name: '新歌单')];
  @override
  Future<SourcePlaylist> ensurePlaylist() async => SourcePlaylist(
      source: source,
      id: FavoriteTargets(box).token(source, account),
      name: '目标');
  @override
  Future<void> apply(SourcePlaylist list, MediaItem song, bool add) async {
    if (wait != null) await wait!.future;
    writes.add((list.id, song.id, add));
    cloud[list.id]!.removeWhere((s) => s.id == song.id);
    if (add) cloud[list.id]!.add(song);
  }

  @override
  Future<FavoritesSnapshot> readSnapshot() async {
    if (failRead) throw const MusicServiceError('无法读取原歌单');
    return FavoritesSnapshot(
        List.of(cloud[FavoriteTargets(box).token(source, account)]!),
        playlistExists: true);
  }

  @override
  Future<List<MediaItem>> readFavorites() async => (await readSnapshot()).songs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryBox box;
  late TargetRemote qq, ne;
  late UnifiedLibrary library;
  setUp(() {
    box = MemoryBox();
    qq = TargetRemote(box, MusicSource.qq);
    ne = TargetRemote(box, MusicSource.netease);
    library = UnifiedLibrary(box,
        remotes: {MusicSource.qq: qq, MusicSource.netease: ne});
  });
  tearDown(() => library.dispose());
  Future<void> select({required bool merge}) async =>
      library.changeTarget(MusicSource.qq, (await qq.targetOptions()).first,
          mergeCurrent: merge);
  test('default and specified targets are independent per platform and account',
      () async {
    await select(merge: false);
    expect(library.targets.get(MusicSource.qq, 'user')?.id, 'new');
    expect(library.targets.get(MusicSource.qq, 'other'), isNull);
    expect(library.targets.get(MusicSource.netease, 'user'), isNull);
    expect(FavoriteTargets(box).token(MusicSource.qq, 'user'), 'new');
    await library.changeTarget(MusicSource.qq, null, mergeCurrent: false);
    expect(library.targets.get(MusicSource.qq, 'user'), isNull);
  });
  test(
      'merge copies old cloud and local songs without deleting destination songs or changing other platform',
      () async {
    qq.cloud['auto'] = [qqSong];
    qq.cloud['new'] = [qqSong.copyWith(id: 'qq:existing')];
    await library.setFavorite(neSong, true);
    await library.sync();
    await select(merge: true);
    expect(qq.cloud['new']!.map((s) => s.id),
        containsAll(['qq:abc', 'qq:existing']));
    expect(qq.cloud['auto']!.map((s) => s.id), ['qq:abc']);
    expect(qq.writes.every((w) => w.$1 == 'new' && w.$3), true);
    expect(ne.cloud['auto'], [neSong]);
  });
  test(
      'no merge keeps existing local favorites and never sends old removals into new target',
      () async {
    await library.setFavorite(qqSong, true);
    await library.sync();
    final removed = qqSong.copyWith(id: 'qq:removed');
    library.entries[sourceKey(removed)] =
        FavoriteEntry(removed, owner: 'user', selected: false);
    await select(merge: false);
    expect(library.contains(qqSong), true);
    expect(qq.cloud['new'], isEmpty);
    expect(qq.writes.where((w) => w.$1 == 'new'), isEmpty);
    final fresh = qqSong.copyWith(id: 'qq:fresh');
    await library.setFavorite(fresh, true);
    await library.sync();
    expect(qq.cloud['new'], [fresh]);
    await library.refreshFromCloud();
    expect(library.contains(qqSong), true);
  });
  test(
      'switch waits for in-flight old writes, then sends merged favorite to new target',
      () async {
    qq.wait = Completer<void>();
    await library.setFavorite(qqSong, true);
    await Future<void>.delayed(Duration.zero);
    final changing = select(merge: true);
    await Future<void>.delayed(Duration.zero);
    qq.wait!.complete();
    qq.wait = null;
    await changing;
    expect(qq.writes.map((w) => w.$1), ['auto', 'new']);
    expect(library.entries[sourceKey(qqSong)]!.target, 'new');
  });
  test('failed old cloud read aborts merge and preserves target', () async {
    qq.failRead = true;
    await expectLater(select(merge: true), throwsA(isA<MusicServiceError>()));
    expect(library.targets.get(MusicSource.qq, 'user'), isNull);
    expect(qq.writes, isEmpty);
  });
  test('another platform playlist and unknown ID are rejected', () async {
    await expectLater(
        library.changeTarget(
            MusicSource.qq,
            const SourcePlaylist(
                source: MusicSource.netease, id: 'new', name: ''),
            mergeCurrent: true),
        throwsA(isA<MusicServiceError>()));
    await expectLater(
        library.changeTarget(
            MusicSource.qq,
            const SourcePlaylist(
                source: MusicSource.qq, id: 'missing', name: ''),
            mergeCurrent: false),
        throwsA(isA<MusicServiceError>()));
  });
}
