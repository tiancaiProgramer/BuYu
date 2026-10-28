// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/music/favorites_auto_sync.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/unified_library.dart';
import 'package:bujuan/common/music/netease_library.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'multi_source_test.dart' show Remote, qqSong, neSong;
import 'aggregate_download_records_test.dart' show NcmApi;
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:bujuan/common/netease_api/src/api/bean.dart';

class SnapshotRemote extends Remote implements FavoritesSnapshotReader {
  List<MediaItem> cloud = [];
  Set<String>? membership;
  bool exists = true, readFails = false;
  int reads = 0, attempts = 0;
  Completer<FavoritesSnapshot>? response;
  void Function()? onApply;
  @override
  Future<FavoritesSnapshot> readSnapshot() async {
    reads++;
    if (readFails) throw const MusicServiceError('读取未完成');
    return response == null
        ? FavoritesSnapshot(List.of(cloud),
            playlistExists: exists, keys: membership)
        : await response!.future;
  }

  @override
  Future<List<MediaItem>> readFavorites() async => (await readSnapshot()).songs;
  @override
  Future<void> apply(SourcePlaylist list, MediaItem song, bool add) async {
    attempts++;
    await super.apply(list, song, add);
    exists = true;
    cloud.removeWhere((s) => sourceKey(s) == sourceKey(song));
    if (add) cloud.add(song);
    onApply?.call();
  }
}

UnifiedLibrary library(MemoryBox box, SnapshotRemote net, SnapshotRemote qq) =>
    UnifiedLibrary(box,
        remotes: {MusicSource.netease: net, MusicSource.qq: qq});

class ConfirmNcm extends NcmApi {
  bool confirm = true;
  @override
  Future<ServerStatusBean> playlistManipulateTracks(
      String id, String tracks, bool add) async {
    if (confirm) {
      this.tracks.removeWhere((t) => t.id == tracks);
      if (add) this.tracks.add(PlayTrackId()..id = tracks);
    }
    return ServerStatusBean()..code = 200;
  }
}

class MissingMetadataNcm extends NcmApi {
  @override
  Future<SongDetailWrap> songDetail(List<String> ids) async => SongDetailWrap()
    ..code = 200
    ..songs = [];
}

class FailingSyncBox extends MemoryBox {
  bool fail = false;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) throw StateError('disk full');
    await super.put(key, value);
  }
}

class IncompleteQq extends QqMusic {
  @override
  bool get loggedIn => true;
  @override
  String get account => 'user1';
  @override
  Future<List<SourcePlaylist>> userPlaylists() async => [
        const SourcePlaylist(
            source: MusicSource.qq, id: '1', name: 'BuYu收藏', count: 150)
      ];
  @override
  Future<List<MediaItem>> playlistSongs(SourcePlaylist list,
          {int page = 1}) async =>
      [qqSong];
}

class IncompleteNcm extends NcmApi {
  @override
  Future<SinglePlayListWrap> playListDetail(String id,
      {int subCount = 5}) async {
    final result = await super.playListDetail(id, subCount: subCount);
    result.playlist!.trackCount = 150;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a slow NetEase write never blocks a new QQ favorite', () async {
    final net = SnapshotRemote()..wait = Completer<void>();
    final qq = SnapshotRemote();
    final store = library(MemoryBox(), net, qq);
    await store.setFavorite(neSong, true);
    await Future<void>.delayed(Duration.zero);
    await store.setFavorite(qqSong, true);
    await Future<void>.delayed(Duration.zero);
    try {
      expect(qq.cloud, [qqSong]);
      expect(net.applied, isEmpty);
    } finally {
      net.wait!.complete();
      await store.sync();
      store.dispose();
    }
  });
  test(
      'truncated QQ and NetEase memberships fail rather than reconciling false deletions',
      () async {
    final qq = IncompleteQq();
    await expectLater(QqFavoritesRemote(qq).readSnapshot(),
        throwsA(isA<MusicServiceError>()));
    qq.dispose();
    final box = MemoryBox()
      ..data[loginData] = {
        'profile': {'userId': 'u1'}
      };
    final api = IncompleteNcm()
      ..data = [
        Play()
          ..id = '5'
          ..userId = 'u1'
          ..name = 'BuYu收藏'
      ]
      ..tracks = [PlayTrackId()..id = '123'];
    await expectLater(NeteaseLibrary(box, api: api).favoritesSnapshot(),
        throwsA(isA<MusicServiceError>()));
  });

  testWidgets('overlapping lifecycle checks share one cloud reconciliation',
      (tester) async {
    final net = SnapshotRemote(),
        qq = SnapshotRemote()..response = Completer<FavoritesSnapshot>();
    final store = library(MemoryBox(), net, qq);
    final auto = FavoritesAutoSync(store);
    auto.start();
    final first = auto.check(), second = auto.check();
    expect(identical(first, second), true);
    await tester.pump();
    expect(qq.reads, 1);
    qq.response!.complete(FavoritesSnapshot([], playlistExists: true));
    await first;
    await tester.pumpAndSettle();
    auto.dispose();
    store.dispose();
  });
  test(
      'failed persistence after remote acknowledgement remains pending and can retry',
      () async {
    final box = FailingSyncBox(), net = SnapshotRemote(), qq = SnapshotRemote();
    final store = library(box, net, qq);
    qq.onApply = () => box.fail = true;
    await store.setFavorite(qqSong, true);
    await store.sync();
    expect(store.pendingCount, 1);
    expect((box.get(UnifiedLibrary.storageKey) as List).single['synced'], -1);
    qq.onApply = null;
    box.fail = false;
    await store.reconcile();
    expect(store.pendingCount, 0);
    expect(store.contains(qqSong), true);
    store.dispose();
  });

  test(
      'account switching during a write cannot mark an old operation synchronized',
      () async {
    final net = SnapshotRemote(), qq = SnapshotRemote();
    final store = library(MemoryBox(), net, qq);
    qq.onApply = () => qq.account = 'another';
    await store.setFavorite(qqSong, true);
    await store.sync();
    expect(store.pendingCount, 1);
    expect(store.entries[sourceKey(qqSong)]!.owner, 'user1');
    expect(store.hasRetryableWork, false);
    store.dispose();
  });
  test(
      'complete cloud snapshots import additions and remove synced deletions by source',
      () async {
    final net = SnapshotRemote()..cloud = [neSong];
    final qq = SnapshotRemote()..cloud = [qqSong];
    final store = library(MemoryBox(), net, qq);
    await store.reconcile();
    expect(store.songs.length, 2);
    qq.cloud = [qqSong.copyWith(id: 'qq:new')];
    await store.reconcile();
    expect(store.contains(qqSong), false);
    expect(store.contains(neSong), true);
    expect(store.songs.map(sourceKey), contains('qq:new'));
    expect(store.pendingCount, 0);
    expect(net.applied, isEmpty);
    expect(qq.applied, isEmpty);
    // A later explicit cloud re-add is imported again.
    qq.cloud.add(qqSong);
    await store.reconcile();
    expect(store.contains(qqSong), true);
    store.dispose();
  });

  test(
      'missing whole playlist is recreated from local songs and never erases them',
      () async {
    final net = SnapshotRemote(), qq = SnapshotRemote()..cloud = [qqSong];
    final store = library(MemoryBox(), net, qq);
    await store.reconcile();
    qq.exists = false;
    qq.cloud.clear();
    await store.reconcile();
    expect(store.contains(qqSong), true);
    expect(qq.cloud, [qqSong]);
    expect(qq.applied, [('qq:abc', true)]);
    expect(store.pendingCount, 0);
    store.dispose();
  });

  test(
      'failed or incomplete source reads never delete local favorites; unavailable metadata retains membership',
      () async {
    final net = SnapshotRemote()..cloud = [neSong];
    final qq = SnapshotRemote()..cloud = [qqSong];
    final store = library(MemoryBox(), net, qq);
    await store.reconcile();
    net.cloud.clear();
    net.membership = {sourceKey(neSong)};
    qq.cloud.clear();
    qq.readFails = true;
    await store.reconcile();
    expect(store.contains(neSong), true);
    expect(store.contains(qqSong), true);
    expect(store.readErrors.keys, [MusicSource.qq]);
    store.dispose();
  });

  test(
      'pending local removal wins over cloud addition and survives restart for automatic retry',
      () async {
    final box = MemoryBox(),
        net = SnapshotRemote(),
        qq = SnapshotRemote()..cloud = [qqSong];
    var store = library(box, net, qq);
    await store.reconcile();
    qq.fail = true;
    await store.setFavorite(qqSong, false);
    await store.reconcile();
    expect(store.contains(qqSong), false);
    expect(store.pendingCount, 1);
    store.dispose();
    qq.fail = false;
    store = library(box, net, qq);
    await store.reconcile();
    expect(store.contains(qqSong), false);
    expect(qq.cloud, isEmpty);
    expect(store.pendingCount, 0);
    store.dispose();
  });

  test('late cloud read cannot erase a local addition completed while reading',
      () async {
    final net = SnapshotRemote(), qq = SnapshotRemote();
    final store = library(MemoryBox(), net, qq);
    qq.response = Completer<FavoritesSnapshot>();
    final pull = store.refreshFromCloud();
    await Future<void>.delayed(Duration.zero);
    await store.setFavorite(qqSong, true);
    await store.sync();
    qq.response!.complete(FavoritesSnapshot([], playlistExists: true));
    await pull;
    expect(store.contains(qqSong), true);
    expect(store.pendingCount, 0);
    store.dispose();
  });

  test(
      'late cloud read cannot resurrect a local removal completed while reading',
      () async {
    final net = SnapshotRemote(), qq = SnapshotRemote()..cloud = [qqSong];
    final store = library(MemoryBox(), net, qq);
    await store.reconcile();
    qq.response = Completer<FavoritesSnapshot>();
    final pull = store.refreshFromCloud();
    await Future<void>.delayed(Duration.zero);
    await store.setFavorite(qqSong, false);
    await store.sync();
    qq.response!.complete(FavoritesSnapshot([qqSong], playlistExists: true));
    await pull;
    expect(store.contains(qqSong), false);
    store.dispose();
  });

  test(
      'changing account never pushes old-account songs or treats its cloud as deletions',
      () async {
    final net = SnapshotRemote(), qq = SnapshotRemote()..cloud = [qqSong];
    final store = library(MemoryBox(), net, qq);
    await store.reconcile();
    qq.account = 'other';
    qq.cloud.clear();
    await store.reconcile();
    expect(store.contains(qqSong), true);
    expect(qq.applied, isEmpty);
    store.dispose();
  });

  test(
      'NetEase confirms membership after successful writes before clearing pending',
      () async {
    final box = MemoryBox()
      ..data[loginData] = {
        'profile': {'userId': 'u1'}
      };
    final api = ConfirmNcm();
    final remote = NeteaseFavoritesRemote(box, api: api);
    const list =
        SourcePlaylist(source: MusicSource.netease, id: '5', name: 'BuYu收藏');
    await remote.apply(list, neSong, true);
    expect(api.tracks.single.id, neSong.id);
    await remote.apply(list, neSong, false);
    expect(api.tracks, isEmpty);
    api.confirm = false;
    await expectLater(
        remote.apply(list, neSong, true), throwsA(isA<MusicServiceError>()));
  });

  test(
      'NetEase snapshot keeps unavailable IDs rather than treating metadata absence as deletion',
      () async {
    final box = MemoryBox()
      ..data[loginData] = {
        'profile': {'userId': 'u1'}
      };
    final api = MissingMetadataNcm()
      ..data = [
        Play()
          ..id = '5'
          ..userId = 'u1'
          ..name = 'BuYu收藏'
      ]
      ..tracks = [PlayTrackId()..id = '123'];
    final snapshot = await NeteaseLibrary(box, api: api).favoritesSnapshot();
    expect(snapshot.keys, {'netease:123'});
    expect(snapshot.playlistExists, true);
    expect(snapshot.songs, isEmpty);
  });

  testWidgets(
      'startup pulls both platforms; failed local write retries automatically without manual taps',
      (tester) async {
    final net = SnapshotRemote()..cloud = [neSong];
    final qq = SnapshotRemote()..fail = true;
    final store = library(MemoryBox(), net, qq);
    final auto = FavoritesAutoSync(store);
    auto.start();
    auto.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(store.contains(neSong), true);
    await store.setFavorite(qqSong, true);
    await tester.pumpAndSettle();
    expect(store.pendingCount, 1);
    final before = qq.attempts;
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(qq.attempts, greaterThan(before));
    qq.fail = false;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(store.pendingCount, 0);
    expect(qq.cloud, [qqSong]);
    auto.dispose();
    store.dispose();
  });

  testWidgets(
      'foreground polling pulls external changes; background checks once then stops timers; resume reconciles',
      (tester) async {
    final net = SnapshotRemote(), qq = SnapshotRemote();
    final store = library(MemoryBox(), net, qq);
    final auto = FavoritesAutoSync(store);
    auto.start();
    auto.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    qq.cloud = [qqSong];
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(store.contains(qqSong), true);
    auto.didChangeAppLifecycleState(AppLifecycleState.hidden);
    auto.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    final reads = qq.reads;
    qq.cloud.clear();
    await tester.pump(const Duration(minutes: 10));
    await tester.pumpAndSettle();
    expect(qq.reads, reads);
    expect(store.contains(qqSong), true);
    auto.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(store.contains(qqSong), false);
    auto.dispose();
    store.dispose();
  });

  testWidgets(
      'logged-out pending work waits without retry loop and resumes after login; dispose cancels timers',
      (tester) async {
    final net = SnapshotRemote(), qq = SnapshotRemote()..account = '';
    final store = library(MemoryBox(), net, qq);
    final auto = FavoritesAutoSync(store);
    auto.start();
    auto.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await store.setFavorite(qqSong, true);
    await tester.pumpAndSettle();
    expect(store.hasRetryableWork, false);
    await tester.pump(const Duration(seconds: 40));
    expect(qq.attempts, 0);
    qq.account = 'user1';
    await store.reconcile(); // The login completion hook.
    expect(qq.cloud, [qqSong]);
    auto.dispose();
    final reads = net.reads;
    await tester.pump(const Duration(minutes: 10));
    expect(net.reads, reads);
    store.dispose();
  });
}
