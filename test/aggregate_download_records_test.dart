// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/audio_quality.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/downloads.dart';
import 'package:bujuan/common/music/netease_library.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/unified_library.dart';
import 'package:bujuan/common/netease_api/src/netease_api.dart';
import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:bujuan/common/netease_api/src/api/bean.dart';
import 'package:bujuan/common/netease_api/src/api/user/bean.dart';
import 'package:flutter_test/flutter_test.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'multi_source_test.dart' show Remote, qqSong, neSong;

class CloudRemote extends Remote implements FavoritesReader {
  List<MediaItem> cloud = [];
  Completer<List<MediaItem>>? response;
  bool readFails = false;
  @override
  Future<List<MediaItem>> readFavorites() async {
    if (readFails) throw const MusicServiceError('cloud offline');
    return response == null ? cloud : await response!.future;
  }
}

class NcmApi extends Fake implements NeteaseMusicApi {
  List<Play> data = [];
  List<PlayTrackId> tracks = [];
  int created = 0, deleted = 0;
  bool confirmRename = true;
  @override
  Future<ServerStatusBean> updateUserPlayListName(
      String id, String name) async {
    if (confirmRename) data.singleWhere((p) => p.id == id).name = name;
    return ServerStatusBean()..code = 200;
  }

  @override
  Future<ServerStatusBean> playlistDelete(List<String> ids) async {
    deleted++;
    data.removeWhere((p) => ids.contains(p.id));
    return ServerStatusBean()..code = 200;
  }

  void Function()? onRead;
  @override
  Future<MultiPlayListWrap2> userPlayList(String userId,
      {int offset = 0, int limit = 30}) async {
    onRead?.call();
    return MultiPlayListWrap2()
      ..code = 200
      ..playlist = data.skip(offset).take(limit).toList();
  }

  @override
  Future<SinglePlayListWrap> playListDetail(String id,
          {int subCount = 5}) async =>
      SinglePlayListWrap()
        ..code = 200
        ..playlist = (Play()
          ..id = id
          ..trackIds = tracks);
  @override
  Future<SongDetailWrap> songDetail(List<String> ids) async => SongDetailWrap()
    ..code = 200
    ..songs = ids
        .map((id) => Song2()
          ..id = id
          ..name = 'net$id')
        .toList();
  @override
  Future<PlaylistCreateWrap> playlistCreate(String name, bool privacy) async {
    created++;
    data.add(Play()
      ..id = 'new'
      ..name = name
      ..userId = 'u1');
    return PlaylistCreateWrap()
      ..code = 200
      ..id = 'new';
  }
}

void main() {
  test(
      'cloud merge combines source identities without writes and survives restart',
      () async {
    final a = CloudRemote()..cloud = [neSong],
        b = CloudRemote()..cloud = [qqSong];
    final box = MemoryBox();
    final library = UnifiedLibrary(box,
        remotes: {MusicSource.netease: a, MusicSource.qq: b});
    await library.refreshFromCloud();
    expect(library.songs.map(sourceKey).toSet(), {'netease:123', 'qq:abc'});
    expect(library.pendingCount, 0);
    await library.sync();
    expect(a.applied, isEmpty);
    expect(b.applied, isEmpty);
    expect(a.created + b.created, 0);
    final restored = UnifiedLibrary(box,
        remotes: {MusicSource.netease: a, MusicSource.qq: b});
    expect(restored.songs.length, 2);
    library.dispose();
    restored.dispose();
  });
  test(
      'cloud refresh preserves pending removals and isolates source failures and switched accounts',
      () async {
    final a = CloudRemote()..cloud = [neSong],
        b = CloudRemote()..cloud = [qqSong];
    final box = MemoryBox();
    final library = UnifiedLibrary(box,
        remotes: {MusicSource.netease: a, MusicSource.qq: b});
    await library.refreshFromCloud();
    b.fail = true;
    await library.setFavorite(qqSong, false);
    await library.sync();
    await library.refreshFromCloud();
    expect(library.contains(qqSong), false);
    expect(library.pendingCount, 1);
    b.fail = false;
    b.readFails = true;
    await library.refreshFromCloud();
    expect(library.contains(neSong), true);
    expect(library.readErrors[MusicSource.qq], isNotNull);
    final empty = UnifiedLibrary(MemoryBox(),
        remotes: {MusicSource.netease: a, MusicSource.qq: b});
    b.readFails = false;
    b.response = Completer<List<MediaItem>>();
    final pull = empty.refreshFromCloud();
    await Future<void>.delayed(Duration.zero);
    b.account = 'other';
    b.response!.complete([qqSong]);
    await pull;
    expect(empty.contains(qqSong), false);
    expect(empty.contains(neSong), true);
    library.dispose();
    empty.dispose();
  });
  test(
      'QQ history retains source metadata and old history can retry after restart',
      () {
    final song = qqSong.copyWith(extras: {
      ...?qqSong.extras,
      'mediaMid': 'media',
      'url': 'https://not-persisted.example/ticket'
    });
    final job = DownloadJob(song, AudioQuality.exhigh)
      ..state = DownloadState.complete
      ..actual = 'MP3 320 kbps'
      ..resolvedQuality = 'exhigh'
      ..received = 123456
      ..savedFolder = 'Music/BuYuPreview'
      ..finishedAt = DateTime(2026, 10, 27)
      ..attempts = 1;
    final raw = job.toMap();
    expect(raw['song']['extras'].containsKey('url'), false);
    final restored = DownloadJob.fromMap(raw);
    expect(restored.song.extras?['mid'], 'abc');
    expect(restored.song.extras?['mediaMid'], 'media');
    expect(restored.actual, 'MP3 320 kbps');
    expect(restored.received, 123456);
    expect(restored.savedFolder, 'Music/BuYuPreview');
    expect(restored.finishedAt, job.finishedAt);
    final old = Map<dynamic, dynamic>.of(raw)
      ..remove('song')
      ..remove('createdAt')
      ..remove('finishedAt');
    final legacy = DownloadJob.fromMap(old);
    expect(legacy.song.extras?['mid'], 'abc');
    expect(legacy.createdAt, isNull);
  });
  test(
      'Netease favorites are read only from own BuYu lists and built-in lists cannot be edited',
      () async {
    final box = MemoryBox();
    await box.put(loginData, {
      'profile': {'userId': 'u1'}
    });
    final api = NcmApi()
      ..data = [
        Play()
          ..id = 'own'
          ..name = 'BuYu收藏'
          ..userId = 'u1',
        Play()
          ..id = 'other'
          ..name = 'BuYu收藏'
          ..userId = 'u2'
      ];
    api.tracks = [PlayTrackId()..id = '123'];
    final library = NeteaseLibrary(box, api: api);
    final songs = await library.favorites();
    expect(songs.single.id, '123');
    expect(api.created, 0);
    api.data = [
      Play()
        ..id = 'built-in'
        ..name = '喜欢的音乐'
        ..userId = 'u1'
        ..specialType = 5
    ];
    await expectLater(
        library.delete(api.data.single), throwsA(isA<MusicServiceError>()));
    api.onRead = () => box.data[loginData] = {
          'profile': {'userId': 'u2'}
        };
    await expectLater(library.lists(), throwsA(isA<MusicServiceError>()));
  });
  test(
      'Netease management requires ownership and verifies cloud readback for all writes',
      () async {
    final box = MemoryBox();
    await box.put(loginData, {
      'profile': {'userId': 'u1'}
    });
    final api = NcmApi();
    final service = NeteaseLibrary(box, api: api);
    await service.create('test');
    expect(api.created, 1);
    expect(api.data.single.name, 'test');
    await service.rename(api.data.single, 'renamed');
    expect(api.data.single.name, 'renamed');
    api.confirmRename = false;
    await expectLater(service.rename(api.data.single, 'not-applied'),
        throwsA(isA<MusicServiceError>()));
    expect(api.data.single.name, 'renamed');
    final owned = api.data.single;
    await service.delete(owned);
    expect(api.data, isEmpty);
    expect(api.deleted, 1);
    api.data.add(Play()
      ..id = 'other'
      ..name = 'not-mine'
      ..userId = 'u2');
    await expectLater(service.rename(api.data.single, 'must-not-write'),
        throwsA(isA<MusicServiceError>()));
    expect(api.data.single.name, 'not-mine');
  });
}
