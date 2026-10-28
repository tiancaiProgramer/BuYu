// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/mixed_search.dart';
import 'package:bujuan/common/music/unified_library.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/audio_quality.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'download_preferences_test.dart' show MemoryBox;

class Remote implements FavoritesRemote {
  @override
  String account = 'user1';
  int created = 0;
  bool fail = false;
  Completer<void>? wait;
  final applied = <(String, bool)>[];
  @override
  Future<SourcePlaylist> ensurePlaylist() async {
    created++;
    return const SourcePlaylist(
        source: MusicSource.qq, id: '5', directory: '7', name: 'BuYu收藏');
  }

  @override
  Future<void> apply(SourcePlaylist list, MediaItem song, bool add) async {
    if (fail) throw StateError('offline');
    if (wait != null) await wait!.future;
    applied.add((sourceKey(song), add));
  }
}

const qqSong = MediaItem(
    id: 'qq:abc',
    title: '同名歌曲',
    extras: {'source': 'qq', 'mid': 'abc', 'qqId': '123'});
const neSong = MediaItem(id: '123', title: '同名歌曲');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('provider identities and QQ original metadata survive persistence', () {
    final item = QqMusic.song({
      'mid': 'abc',
      'id': 123,
      'title': '同名歌曲',
      'interval': 120,
      'singer': [
        {'name': '歌手', 'mid': 'artist'}
      ],
      'album': {'mid': 'album', 'name': '专辑'},
      'file': {'media_mid': 'media', 'size_flac': 1000}
    });
    expect(item.id, 'qq:abc');
    expect(sourceKey(item), 'qq:abc');
    expect(sourceKey(neSong), 'netease:123');
    expect(restoreSong(saveSong(item)).extras?['mediaMid'], 'media');
    expect(
        QqMusic.parseCookies(
            'uin=o00123; qqmusic_key=fake-session; unrelated=never-saved'),
        {'uin': 'o00123', 'qqmusic_key': 'fake-session'});
    expect(() => QqMusic.parseCookies('uin=123\nInjected=1'),
        throwsA(isA<MusicServiceError>()));
  });
  test(
      'mixed search is progressive, isolates failures and ignores obsolete results',
      () async {
    final a = Completer<List<MediaItem>>(), b = Completer<List<MediaItem>>();
    final search = MixedSearch(providers: {
      MusicSource.netease: (query, page) =>
          query == 'old' ? a.future : Future.value([neSong]),
      MusicSource.qq: (query, page) =>
          query == 'old' ? b.future : Future.error(StateError('offline'))
    });
    final old = search.search('old');
    a.complete([neSong]);
    await Future<void>.delayed(Duration.zero);
    expect(search.songs, [neSong]);
    expect(search.busy, contains(MusicSource.qq));
    await search.search('new');
    b.complete([qqSong]);
    await old;
    expect(search.songs, [neSong]);
    expect(search.errors.keys, [MusicSource.qq]);
    search.dispose();
  });
  test(
      'same titles coexist, pending changes persist, remote writes route by source',
      () async {
    final box = MemoryBox(), a = Remote(), b = Remote();
    a.account = '';
    b.account = '';
    final library = UnifiedLibrary(box,
        remotes: {MusicSource.netease: a, MusicSource.qq: b});
    await library.setFavorite(neSong, true);
    await library.setFavorite(qqSong, true);
    await library.sync();
    expect(library.songs.length, 2);
    expect(library.pendingCount, 2);
    expect(a.created, 0);
    library.dispose();
    final restored = UnifiedLibrary(box,
        remotes: {MusicSource.netease: a, MusicSource.qq: b});
    a.account = 'net-user';
    b.account = 'qq-user';
    await restored.sync();
    expect(a.applied, [('netease:123', true)]);
    expect(b.applied, [('qq:abc', true)]);
    expect(restored.pendingCount, 0);
    b.fail = true;
    await restored.setFavorite(qqSong, false);
    await restored.sync();
    expect(restored.contains(qqSong), false);
    expect(restored.pendingCount, 1);
    final tombstone = FavoriteEntry.fromMap(
        (box.get(UnifiedLibrary.storageKey) as List).last as Map);
    expect(tombstone.selected, false);
    expect(tombstone.pending, true);
    b.fail = false;
    await restored.sync();
    expect(b.applied.last, ('qq:abc', false));
    expect(restored.pendingCount, 0);
    restored.dispose();
  });
  test('account changes cannot send old favorites to a different user',
      () async {
    final a = Remote(), b = Remote()..fail = true;
    final library = UnifiedLibrary(MemoryBox(),
        remotes: {MusicSource.netease: a, MusicSource.qq: b});
    await library.setFavorite(qqSong, true);
    await library.sync();
    b.account = 'another-user';
    b.fail = false;
    await library.sync();
    expect(b.applied, isEmpty);
    expect(library.pendingCount, 1);
    expect(library.entries['qq:abc']!.error, contains('其他'));
    library.dispose();
  });
  test('rapid unfavorite and new items during sync are not lost', () async {
    final a = Remote(), b = Remote()..wait = Completer<void>();
    final library = UnifiedLibrary(MemoryBox(),
        remotes: {MusicSource.netease: a, MusicSource.qq: b});
    await library.setFavorite(qqSong, true);
    await Future<void>.delayed(Duration.zero);
    await library.setFavorite(qqSong, false);
    final other = qqSong.copyWith(id: 'qq:other');
    await library.setFavorite(other, true);
    b.wait!.complete();
    await library.sync();
    expect(
        b.applied,
        containsAllInOrder(
            [('qq:abc', true), ('qq:abc', false), ('qq:other', true)]));
    expect(library.pendingCount, 0);
    expect(library.songs.single.id, 'qq:other');
    library.dispose();
  });
  test('QQ search and playback keep independent cookies and returned quality',
      () async {
    const channel = MethodChannel('buyu/qqmusic-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'readSession'
                ? 'uin=o00123; qqmusic_key=test-key'
                : null);
    final dio = Dio();
    final methods = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final body = o.data as Map;
      final req = body['req_0'] as Map;
      methods.add(req['method'] as String);
      expect(o.uri.host, 'u.y.qq.com');
      expect(o.headers['Cookie'], contains('qqmusic_key=test-key'));
      expect(o.headers['Cookie'], isNot(contains('MUSIC_U')));
      Map data;
      if (req['method'] == 'do_search_v2') {
        data = {
          'body': {
            'item_song': {
              'items': [
                {
                  'mid': 'abc',
                  'id': 123,
                  'title': '测试',
                  'file': {'media_mid': 'media'}
                }
              ]
            }
          }
        };
      } else {
        final filename =
            ((req['param'] as Map)['filename'] as List).single as String;
        expect(filename, anyOf('F000media.flac', 'M800media.mp3'));
        data = {
          'sip': ['https://dl.stream.qqmusic.qq.com/'],
          'midurlinfo': [
            {
              'purl': filename.startsWith('F000')
                  ? ''
                  : 'M800media.mp3?vkey=retained'
            }
          ]
        };
      }
      h.resolve(Response(requestOptions: o, data: {
        'code': 0,
        'req_0': {'code': 0, 'data': data}
      }));
    }));
    final qq = QqMusic(dio: dio, channel: channel);
    final list = await qq.search('测试');
    expect(list.single.id, 'qq:abc');
    final audio = await qq.audio(list.single, AudioQuality.lossless);
    expect(audio.quality, AudioQuality.exhigh);
    expect(audio.url, endsWith('?vkey=retained'));
    expect(methods, ['do_search_v2', 'CgiGetVkey', 'CgiGetVkey']);
    qq.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('QQ login validates a candidate without replacing the active session',
      () async {
    const channel = MethodChannel('buyu/qqmusic-login-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var failSave = true;
    final validation = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readSession')
        return 'uin=123; qqmusic_key=old-test-key';
      if (call.method == 'login')
        return 'uin=9; qqmusic_uin=456; qqmusic_key=new-test-key';
      if (call.method == 'saveSession' && failSave)
        throw PlatformException(code: 'storage');
      return null;
    });
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      expect(o.uri.host, 'c6.y.qq.com');
      expect(o.queryParameters['userid'], '456');
      expect(o.headers['Cookie'], contains('new-test-key'));
      await validation.future;
      h.resolve(Response(requestOptions: o, data: {
        'code': 0,
        'data': {
          'creator': {'uin': '456', 'nick': '测试账号'}
        }
      }));
    }));
    final qq = QqMusic(dio: dio, channel: channel);
    await qq.restore();
    final attempt = qq.login();
    await Future<void>.delayed(Duration.zero);
    expect(qq.account, '123');
    validation.complete();
    await expectLater(attempt, throwsA(isA<PlatformException>()));
    expect(qq.account, '123');
    failSave = false;
    expect(await qq.login(), isTrue);
    expect(qq.account, '456');
    expect(qq.nickname, '测试账号');
    qq.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('QQ cloud business failures are not marked as successful writes',
      () async {
    const channel = MethodChannel('buyu/qqmusic-cloud-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'readSession'
            ? 'uin=123; qqmusic_key=test-key'
            : null);
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final method = (o.data as Map)['req_0']['method'];
      final data = method == 'get_song_detail_yqq'
          ? {
              'track_info': {'id': 123, 'mid': 'abc', 'type': 0}
            }
          : method == 'GetPlaylistByUin'
              ? {
                  'v_playlist': [
                    {
                      'id': 50,
                      'tid': 0,
                      'dirId': 7,
                      'title': 'BuYu收藏',
                      'picUrl': '',
                      'songNum': 1
                    }
                  ]
                }
              : {'retCode': 1000};
      h.resolve(Response(requestOptions: o, data: {
        'code': 0,
        'req_0': {'code': 0, 'data': data}
      }));
    }));
    final qq = QqMusic(dio: dio, channel: channel);
    final list = await qq.createFavorites();
    expect(list.id, '50');
    expect(list.directory, '7');
    await expectLater(
        qq.syncFavorite(list, qqSong, true), throwsA(isA<MusicServiceError>()));
    qq.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test(
      'completed web session retries without another login and rejects anonymous or mismatched profiles',
      () async {
    const channel = MethodChannel('buyu/qqmusic-web-retry-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var opened = 0, saved = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readWebSession')
        return 'uin=456; qqmusic_key=test-key';
      if (call.method == 'login') {
        opened++;
        return null;
      }
      if (call.method == 'saveSession') saved++;
      return null;
    });
    var result = <String, dynamic>{'code': 1000};
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        expect(o.method, 'GET');
        expect(o.followRedirects, isFalse);
        expect(o.uri.host, 'c6.y.qq.com');
        expect(o.headers['Cookie'], isNot(contains('MUSIC_U')));
        h.resolve(Response(requestOptions: o, data: result));
      }));
    final qq = QqMusic(dio: dio, channel: channel);
    await expectLater(qq.login(), throwsA(isA<MusicServiceError>()));
    expect(qq.loggedIn, isFalse);
    expect(saved, 0);
    result = {
      'code': 0,
      'data': {
        'creator': {'uin': '123', 'nick': '其他账号'}
      }
    };
    await expectLater(qq.login(), throwsA(isA<MusicServiceError>()));
    expect(saved, 0);
    result = {
      'code': 0,
      'data': {
        'creator': {'uin': '456', 'nick': '测试账号'}
      }
    };
    expect(await qq.login(), isTrue);
    expect(qq.account, '456');
    expect(saved, 1);
    expect(opened, 0);
    expect(await qq.login(fresh: true), isFalse);
    expect(opened, 1);
    expect(qq.account, '456');
    qq.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('authenticated web profiles with masked numeric IDs remain usable',
      () async {
    const channel = MethodChannel('buyu/qqmusic-masked-profile-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'readWebSession'
            ? 'uin=456; qqmusic_key=test-key'
            : null);
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        h.resolve(Response(requestOptions: o, data: {
          'code': 0,
          'data': {
            'creator': {'uin': 0, 'nick': '测试账号'}
          }
        }));
      }));
    final qq = QqMusic(dio: dio, channel: channel);
    expect(await qq.login(), isTrue);
    expect(qq.account, '456');
    qq.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('QQ playlist booleans and readback confirm real cloud changes',
      () async {
    const channel = MethodChannel('buyu/qqmusic-readback-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'readSession'
            ? 'uin=456; qqmusic_key=test-key'
            : null);
    final dio = Dio();
    var present = false, noOp = false, readError = false;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final req = (o.data as Map)['req_0'] as Map;
      final method = req['method'];
      Map data;
      if (method == 'get_song_detail_yqq') {
        data = {
          'track_info': {'id': 123, 'mid': 'abc', 'type': 0}
        };
      } else if (method == 'CgiGetDiss') {
        final param = req['param'] as Map;
        expect(param['tag'], 1);
        expect(param['userinfo'], 1);
        expect(param['orderlist'], 1);
        expect(param['onlysonglist'], 0);
        data = readError
            ? {'code': 2000}
            : {
                'code': 0,
                'total_song_num': present ? 1 : 0,
                'songlist': present
                    ? [
                        {'mid': 'abc', 'id': 123, 'title': '测试'}
                      ]
                    : []
              };
      } else {
        expect(req['param']['bFmtUtf8'], isTrue);
        if (!noOp) present = method == 'AddSonglist';
        data = {'retCode': 0};
      }
      h.resolve(Response(requestOptions: o, data: {
        'code': 0,
        'req_0': {'code': 0, 'data': data}
      }));
    }));
    final qq = QqMusic(dio: dio, channel: channel);
    const list = SourcePlaylist(
        source: MusicSource.qq, id: '50', directory: '7', name: 'BuYu收藏');
    await qq.syncFavorite(list, qqSong, true);
    expect(present, isTrue);
    await qq.syncFavorite(list, qqSong, false);
    expect(present, isFalse);
    noOp = true;
    await expectLater(
        qq.syncFavorite(list, qqSong, true), throwsA(isA<MusicServiceError>()));
    readError = true;
    await expectLater(
        qq.playlistSongs(list), throwsA(isA<MusicServiceError>()));
    qq.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('old QQ acknowledgements require cloud readback once after upgrading',
      () {
    final old = FavoriteEntry(qqSong, synced: 0).toMap()
      ..remove('cloudReadbackVersion');
    final migrated = FavoriteEntry.fromMap(old);
    expect(migrated.selected, isTrue);
    expect(migrated.pending, isTrue);
    expect(FavoriteEntry.fromMap(migrated.toMap()).pending, isTrue);
    migrated.synced = migrated.revision;
    expect(FavoriteEntry.fromMap(migrated.toMap()).pending, isFalse);
    final net = FavoriteEntry(neSong, synced: 0).toMap()
      ..remove('cloudReadbackVersion');
    expect(FavoriteEntry.fromMap(net).pending, isFalse);
  });
  test('QQ playlist metadata omissions fall back to the official web detail',
      () async {
    const channel = MethodChannel('buyu/qqmusic-playlist-fallback-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'readSession'
            ? 'uin=456; qqmusic_key=test-key'
            : null);
    var webReads = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final web = o.uri.host == 'c.y.qq.com';
        if (web) {
          webReads++;
          expect(o.headers['Cookie'], contains('test-key'));
          expect(o.followRedirects, isFalse);
        }
        h.resolve(Response(
            requestOptions: o,
            data: web
                ? {
                    'code': 0,
                    'cdlist': [
                      {
                        'disstid': '50',
                        'dissid': 5,
                        'songlist': [
                          {'mid': 'abc', 'id': 123, 'title': '测试'}
                        ]
                      }
                    ]
                  }
                : {
                    'code': 0,
                    'req_0': {
                      'code': 0,
                      'data': {'code': 0, 'total_song_num': 1, 'songlist': []}
                    }
                  }));
      }));
    final qq = QqMusic(dio: dio, channel: channel);
    const list = SourcePlaylist(
        source: MusicSource.qq, id: '50', directory: '7', name: 'BuYu收藏');
    expect((await qq.playlistSongs(list)).single.id, 'qq:abc');
    expect(webReads, 1);
    qq.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('QQ private web list IDs may be masked while real mismatches fail',
      () async {
    const channel = MethodChannel('buyu/qqmusic-private-list-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'readSession'
            ? 'uin=456; qqmusic_key=test-key'
            : null);
    var returnedId = '0';
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final web = o.uri.host == 'c.y.qq.com';
        h.resolve(Response(
            requestOptions: o,
            data: web
                ? {
                    'code': 0,
                    'cdlist': [
                      {
                        'disstid': returnedId,
                        'songlist': [
                          {'mid': 'abc', 'id': 123, 'title': '测试'}
                        ]
                      }
                    ]
                  }
                : {
                    'code': 0,
                    'req_0': {
                      'code': 0,
                      'data': {'code': 0, 'total_song_num': 1, 'songlist': []}
                    }
                  }));
      }));
    final qq = QqMusic(dio: dio, channel: channel);
    const list = SourcePlaylist(
        source: MusicSource.qq, id: '50', directory: '7', name: 'BuYu收藏');
    expect((await qq.playlistSongs(list)).single.id, 'qq:abc');
    returnedId = '51';
    await expectLater(
        qq.playlistSongs(list), throwsA(isA<MusicServiceError>()));
    qq.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('QQ favorites use the detail type and clean up an obsolete search entity type', () async {
    const channel = MethodChannel('buyu/qqmusic-song-type-test');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'readSession' ? 'uin=456; qqmusic_key=test-key' : null);
    final types = <int>{1};
    var identityMismatch = false;
    final dio = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final req = (o.data as Map)['req_0'] as Map;
      Map data;
      if (req['method'] == 'get_song_detail_yqq') {
        data = {'track_info': {'id': 123, 'mid': identityMismatch ? 'another' : 'abc', 'type': 0}};
      } else if (req['method'] == 'CgiGetDiss') {
        data = {'code': 0, 'total_song_num': types.length, 'songlist': types.contains(0) ? [{'mid': 'abc', 'id': 123, 'title': '测试', 'type': 0}] : []};
      } else {
        final type = req['param']['v_songInfo'][0]['songType'] as int;
        if (req['method'] == 'AddSonglist') { types.add(type); } else { types.remove(type); }
        data = {'retCode': 0};
      }
      h.resolve(Response(requestOptions: o, data: {'code': 0, 'req_0': {'code': 0, 'data': data}}));
    }));
    final qq = QqMusic(dio: dio, channel: channel);
    const list = SourcePlaylist(source: MusicSource.qq, id: '50', directory: '7', name: 'BuYu收藏');
    final track = qqSong.copyWith(extras: {...?qqSong.extras, 'songType': 1});
    await qq.syncFavorite(list, track, true);
    expect(types, {0});
    await qq.syncFavorite(list, track, false);
    expect(types, isEmpty);
    identityMismatch = true;
    await expectLater(qq.syncFavorite(list, track, true), throwsA(isA<MusicServiceError>()));
    expect(types, isEmpty);
    qq.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
