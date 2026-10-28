// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:bujuan/common/downloads.dart';
import 'package:bujuan/common/audio_quality.dart';
import 'package:get_it/get_it.dart';
import 'package:bujuan/common/music/local_folders.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_library_api.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/music/qq_qr_login.dart';
import 'package:bujuan/pages/music/playlist_source_filter.dart';
import 'package:bujuan/pages/user/personal_landscape.dart';
import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'multi_source_test.dart' show qqSong, neSong;

class SlowBox extends MemoryBox {
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (fail) throw StateError('disk full');
    if (gate != null) await gate!.future;
    await super.put(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'local folders preserve mixed identities and concurrent edits across restart',
      () async {
    final box = SlowBox(), folders = LocalFolders(SlowBox());
    final data = LocalFolders(box);
    await data.create('通勤');
    final id = data.folders.single.id;
    box.gate = Completer<void>();
    final a = data.putSong(id, qqSong, true),
        b = data.putSong(id, neSong, true);
    box.gate!.complete();
    await Future.wait([a, b]);
    box.gate = null;
    final restored = LocalFolders(box);
    expect(restored.folders.single.songs.map(sourceKey).toSet(),
        {'qq:abc', 'netease:123'});
    await data.rename(id, '运动');
    expect(data.folders.single.name, '运动');
    box.fail = true;
    await expectLater(data.remove(id), throwsStateError);
    expect(data.folders.single.songs.length, 2);
    box.fail = false;
    await data.putSong(id, qqSong, false);
    expect(data.folders.single.songs.single.id, '123');
    await data.remove(id);
    expect(data.folders, isEmpty);
    folders.dispose();
    data.dispose();
    restored.dispose();
  });
  test('QQ QR acquisition never forwards music credentials and rejects expiry',
      () async {
    final dio = Dio();
    final paths = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      paths.add(o.uri.path);
      expect(o.headers['Cookie'],
          paths.length == 1 ? isNull : 'qrsig=test-signature');
      if (o.uri.path == '/ptqrshow')
        h.resolve(Response(
            requestOptions: o,
            data: [137, 80, 78, 71, 13, 10, 26, 10],
            headers: Headers.fromMap({
              'set-cookie': ['qrsig=test-signature; Secure; HttpOnly']
            })));
      else
        h.resolve(Response(
            requestOptions: o, data: "ptuiCB('65','0','','0','expired','');"));
    }));
    final qr = QqQrLogin(dio: dio);
    expect((await qr.create()).length, 8);
    final qq = QqMusic();
    await expectLater(qr.check(qq), throwsA(isA<MusicServiceError>()));
    expect(await qr.check(qq), isNull);
    expect(paths, ['/ptqrshow', '/ptqrlogin']);
    qr.close();
    qq.dispose();
  });
  test('QQ comment pagination carries cursor and rejects business failures',
      () async {
    final dio = Dio();
    var fail = false;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final req = (o.data as Map)['req_0'] as Map;
      expect(req['module'], 'music.globalComment.CommentRead');
      expect(req['method'], 'GetNewCommentList');
      expect(req['param']['PageNum'], 1);
      expect(req['param']['LastCommentSeqNo'], 'next');
      h.resolve(Response(requestOptions: o, data: {
        'code': 0,
        'req_0': {
          'code': 0,
          'data': {
            'SubCode': fail ? 3 : 0,
            'CommentList': {
              'HasMore': 1,
              'Comments': [
                {'CmId': 'one', 'SeqNo': 'two', 'Content': 'hello'}
              ]
            }
          }
        }
      }));
    }));
    final qq = QqMusic(dio: dio);
    final page =
        await qq.songComments(qqSong, hot: false, page: 2, cursor: 'next');
    expect(page.cursor, 'two');
    expect(page.more, true);
    fail = true;
    await expectLater(
        qq.songComments(qqSong, hot: false, page: 2, cursor: 'next'),
        throwsA(isA<MusicServiceError>()));
    qq.dispose();
  });
  test(
      'QQ management blocks built-in folders and requires own list before mutation',
      () async {
    const channel = MethodChannel('buyu/qq-management-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'readSession'
                ? 'uin=123; qqmusic_key=test'
                : null);
    final dio = Dio();
    final methods = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      final method = (o.data as Map)['req_0']['method'] as String;
      methods.add(method);
      h.resolve(Response(requestOptions: o, data: {
        'code': 0,
        'req_0': {
          'code': 0,
          'data': {
            'v_playlist': [
              {'tid': 8, 'dirId': 201, 'dirName': '我喜欢'}
            ]
          }
        }
      }));
    }));
    final qq = QqMusic(dio: dio, channel: channel);
    await qq.restore();
    const builtin = SourcePlaylist(
        source: MusicSource.qq, id: '8', directory: '201', name: '我喜欢');
    await expectLater(
        qq.deletePlaylist(builtin), throwsA(isA<MusicServiceError>()));
    expect(methods, ['GetPlaylistByUin']);
    qq.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('QQ download resolves only the logged-in source and preserves file size and signed URL', () async {
    const channel=MethodChannel('buyu/qq-download-test');
    final messenger=TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel,(call) async=>call.method=='readSession'?'uin=123; qqmusic_key=fake':null);
    final dio=Dio(); final methods=<String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest:(o,h){
      final req=(o.data as Map)['req_0'] as Map; final method=req['method'] as String;methods.add(method);
      final data=method=='get_song_detail_yqq'?{'track_info':{'mid':'abc','id':123,'type':0,'title':'song','file':{'media_mid':'file-mid','size_320mp3':123456}}}:{'sip':['https://dl.stream.qqmusic.qq.com/'],'midurlinfo':[{'purl':'M800file-mid.mp3?vkey=preserved'}]};
      h.resolve(Response(requestOptions:o,data:{'code':0,'req_0':{'code':0,'data':data}}));
    }));
    final qq=QqMusic(dio:dio,channel:channel);GetIt.I.registerSingleton<QqMusic>(qq);
    try {
      final source=await Downloads.resolveOfficial(qqSong,AudioQuality.exhigh);
      expect(source.url,'https://dl.stream.qqmusic.qq.com/M800file-mid.mp3?vkey=preserved');expect(source.size,123456);expect(source.level,'exhigh');
      expect(methods,['get_song_detail_yqq','CgiGetVkey']);
    } finally {await GetIt.I.reset();qq.dispose();messenger.setMockMethodCallHandler(channel,null);}
  });
  for (final size in [const Size(844, 390), const Size(640, 300)]) {
    testWidgets(
        'source controls and collapsed cloud leave local card usable at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var source = PlaylistSource.all;
      var expanded = true;
      var localOpened = false;
      await tester.pumpWidget(MaterialApp(
          home: StatefulBuilder(
              builder: (context, setState) => PersonalLandscape(
                    nickname: '',
                    avatar: '',
                    liked: Play(),
                    playlists: [
                      Play()
                        ..id = 'local'
                        ..name = '本地收藏',
                      if (expanded && source != PlaylistSource.qq)
                        Play()
                          ..id = 'net'
                          ..name = '网易云歌单',
                      if (expanded && source != PlaylistSource.netease)
                        Play()
                          ..id = 'qq'
                          ..name = 'QQ歌单'
                    ],
                    actions: const [],
                    onPlaylist: (p) => localOpened = p.id == 'local',
                    onAvatar: () {},
                    onSearch: () {},
                    onManage: () {},
                    playlistFilter: Row(children: [
                      Expanded(
                          child: PlaylistSourceFilter(
                              value: source,
                              onChanged: (s) => setState(() => source = s))),
                      IconButton(
                          tooltip: '折叠云端歌单',
                          onPressed: () => setState(() => expanded = !expanded),
                          icon: const Icon(Icons.expand_less))
                    ]),
                  ))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('playlist-source:qq')));
      await tester.pumpAndSettle();
      expect(find.text('网易云歌单'), findsNothing);
      expect(find.text('本地收藏'), findsOneWidget);
      await tester.tap(find.byTooltip('折叠云端歌单'));
      await tester.pumpAndSettle();
      expect(find.text('QQ歌单'), findsNothing);
      await tester.tap(find.text('本地收藏'));
      expect(localOpened, true);
      expect(tester.takeException(), isNull);
    });
  }
}
