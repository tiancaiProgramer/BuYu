// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_discovery.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/pages/music/discovery_sources.dart';
import 'package:bujuan/pages/music/qq_discovery_views.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

final fixtureSong = QqMusic.song({
  'mid': 'fixture-song',
  'id': 123,
  'title': '节目',
  'interval': 2400,
  'singer': [
    {'name': '主播'}
  ],
  'album': {'mid': 'album', 'name': '专辑'},
  'file': {'media_mid': 'audio-mid', 'size_128mp3': 12345}
});

class FakeQqDiscoveryClient extends QqMusic {
  String accountId = '123';
  final calls = <(String, String, Map<String, dynamic>)>[];
  Future<Map> Function(String, String, Map<String, dynamic>)? respond;
  final lists = <SourcePlaylist>[];
  Completer<List<MediaItem>>? pending;
  @override
  bool get loggedIn => accountId.isNotEmpty;
  @override
  String get account => accountId;
  @override
  Future<void> restore() async {}
  @override
  Future<Map> rpc(String module, String method, Map<String, dynamic> param,
      {CancelToken? cancelToken,
      bool auth = false,
      String? expectedAccount}) async {
    expect(auth, true);
    expect(expectedAccount, accountId);
    calls.add((module, method, param));
    return respond == null ? {} : await respond!(module, method, param);
  }

  @override
  Future<List<MediaItem>> playlistSongs(SourcePlaylist list,
      {int page = 1}) async {
    lists.add(list);
    return pending == null ? [fixtureSong] : await pending!.future;
  }
}

class _Catalog extends QqDiscovery {
  _Catalog(super.qq);
  @override
  Future<List<MediaItem>> dailySongs(
          {bool refresh = false, CancelToken? cancelToken}) async =>
      [fixtureSong];
  @override
  Future<List<QqPodcast>> podcasts(
          {String query = '播客',
          int page = 1,
          CancelToken? cancelToken}) async =>
      [const QqPodcast(id: 'podcast', name: '真实QQ播客', author: '播客主播')];
  @override
  Future<List<MediaItem>> podcastEpisodes(QqPodcast podcast,
          {int page = 1, CancelToken? cancelToken}) async =>
      [fixtureSong];
}

void main() {
  test(
      'daily uses only the native subtype510 playlist and its directory, never radio',
      () async {
    final qq = FakeQqDiscoveryClient();
    qq.respond = (_, __, ___) async => {
          'v_shelf': [
            {
              'v_niche': [
                {
                  'v_card': [
                    {'subtype': 0, 'id': '777'},
                    {
                      'subtype': 510,
                      'id': '1234567890',
                      'miscellany': {'dirid': '301'}
                    }
                  ]
                }
              ]
            }
          ]
        };
    final api = QqDiscovery(qq);
    expect(await api.dailySongs(), [fixtureSong]);
    expect(qq.lists.single.id, '1234567890');
    expect(qq.lists.single.directory, '301');
    expect(await api.dailySongs(), [fixtureSong]);
    expect(qq.calls.length, 1);
    await api.dailySongs(refresh: true);
    expect(qq.calls.length, 2);
    expect(qq.calls.every((c) => c.$2 == 'get_recommend_feed'), true);
    qq.dispose();
  });
  test(
      'missing or ambiguous daily cards are a failure instead of unrelated recommendations',
      () async {
    final qq = FakeQqDiscoveryClient();
    final api = QqDiscovery(qq);
    for (final cards in [
      [
        {'subtype': 0, 'id': '1'}
      ],
      [
        {'subtype': 510, 'id': '1'},
        {'subtype': 510, 'id': '2'}
      ]
    ]) {
      qq.respond = (_, __, ___) async => {'cards': cards};
      await expectLater(
          api.dailySongs(refresh: true), throwsA(isA<MusicServiceError>()));
    }
    expect(qq.lists, isEmpty);
    qq.dispose();
  });
  test('changing QQ account during daily load never returns old-account songs',
      () async {
    final qq = FakeQqDiscoveryClient();
    final api = QqDiscovery(qq);
    qq.respond = (_, __, ___) async => {
          'card': {'subtype': 510, 'id': '1'}
        };
    qq.pending = Completer<List<MediaItem>>();
    final loading = api.dailySongs();
    await Future<void>.delayed(Duration.zero);
    qq.accountId = '456';
    qq.pending!.complete([fixtureSong]);
    await expectLater(loading, throwsA(isA<MusicServiceError>()));
    qq.dispose();
  });
  test('QQ FM uses supported empty history and filters recent songs locally',
      () async {
    final qq = FakeQqDiscoveryClient();
    qq.respond = (module, method, param) async {
      expect(module, 'music.radioProxy.MbTrackRadioSvr');
      expect(method, 'get_radio_track');
      expect(param['song_ids'], isEmpty);
      return {
        'tracks': [
          {
            'mid': 'recent-mid',
            'id': 123,
            'title': '近期已播放',
          },
          {
            'mid': 'fm-mid',
            'id': 234,
            'title': 'FM歌曲',
            'file': {'media_mid': 'file-mid'}
          }
        ]
      };
    };
    final result =
        await QqDiscovery(qq).radioSongs(recentIds: {'123', 'qq:invalid'});
    expect(result.single.id, 'qq:fm-mid');
    expect(result.single.extras?['mediaMid'], 'file-mid');
    qq.accountId = '';
    await expectLater(
        QqDiscovery(qq).radioSongs(), throwsA(isA<MusicServiceError>()));
    expect(qq.calls.length, 1);
    qq.dispose();
  });
  test('QQ FM returns an empty fresh batch so the handler can retry duplicates',
      () async {
    final qq = FakeQqDiscoveryClient();
    qq.respond = (_, __, param) async {
      expect(param['song_ids'], isEmpty);
      return {'tracks': [{'mid': 'recent-mid', 'id': 123}]};
    };
    expect(await QqDiscovery(qq).radioSongs(recentIds: {'123'}), isEmpty);
    qq.dispose();
  });
  test(
      'podcast catalog admits only QQ podcast hosts and their native voice albums',
      () async {
    final qq = FakeQqDiscoveryClient();
    qq.respond = (module, method, param) async {
      if (method == 'do_search_v2') {
        expect(param['search_type'], 1);
        return {
          'body': {
            'direct_result': {
              'items': [
                {
                  'title': '播客主播',
                  'custom_info': {
                    'singer_identity': '14',
                    'mid': '0037qcOG4VUhJR'
                  }
                },
                {
                  'title': '普通歌手',
                  'custom_info': {
                    'singer_identity': '1',
                    'mid': '00000000000000'
                  }
                }
              ]
            }
          },
          'meta': {'sum': 1}
        };
      }
      expect(module, 'music.musichallAlbum.AlbumListServer');
      expect(param['singerMid'], '0037qcOG4VUhJR');
      return {
        'albumList': [
          {
            'albumMid': 'real-podcast',
            'albumName': '真实播客',
            'albumType': '人声音频',
            'singerName': '主播',
            'pmid': 'cover_3'
          },
          {'albumMid': 'music', 'albumName': '音乐专辑', 'albumType': '录音室专辑'}
        ]
      };
    };
    final api = QqDiscovery(qq);
    final result = await api.podcasts();
    expect(result.single.id, 'real-podcast');
    expect(result.single.image, contains('cover_3.jpg'));
    expect(api.podcastsHaveMore, false);
    qq.dispose();
  });
  test('native podcast episode metadata and cover remain bound to QQ playback',
      () async {
    final qq = FakeQqDiscoveryClient();
    qq.respond = (_, method, param) async {
      expect(method, 'GetAlbumSongList');
      expect(param['albumMid'], 'podcast-mid');
      expect(param['begin'], 50);
      return {
        'songList': [
          {
            'songInfo': {
              'mid': 'episode-mid',
              'id': 99,
              'title': '一期节目',
              'interval': 3600,
              'type': 0,
              'file': {'media_mid': 'file-mid'}
            }
          }
        ]
      };
    };
    final result = await QqDiscovery(qq).podcastEpisodes(
        const QqPodcast(
            id: 'podcast-mid',
            name: '播客',
            image: 'https://y.gtimg.cn/cover.jpg'),
        page: 2);
    expect(result.single.id, 'qq:episode-mid');
    expect(result.single.duration, const Duration(hours: 1));
    expect(result.single.extras?['qqPodcast'], true);
    expect(result.single.extras?['mediaMid'], 'file-mid');
    expect(result.single.artUri.toString(), 'https://y.gtimg.cn/cover.jpg');
    qq.dispose();
  });
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets(
        'daily and podcasts select the logged-in source without cross-platform requests at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final statuses = {MusicSource.netease: false, MusicSource.qq: true};
      var netLoads = 0, qqLoads = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DiscoverySources(
                  id: 'test',
                  statusReader: (s) => statuses[s]!,
                  netease: (_) {
                    netLoads++;
                    return const Text('网易云内容');
                  },
                  qq: (_) {
                    qqLoads++;
                    return const Text('QQ内容');
                  }))));
      await tester.pumpAndSettle();
      expect(netLoads, 0);
      expect(qqLoads, 1);
      await tester.tap(find.byKey(const ValueKey('discovery-source:netease')));
      await tester.pumpAndSettle();
      expect(find.text('请登录网易云账号'), findsOneWidget);
      expect(netLoads, 0);
      statuses[MusicSource.netease] = true;
      await tester.tap(find.byKey(const ValueKey('discovery-source:qq')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('discovery-source:netease')));
      await tester.pumpAndSettle();
      expect(find.text('网易云内容'), findsOneWidget);
      expect(netLoads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await GetIt.I.reset();
    });
  }
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(640, 300)
  ]) {
    testWidgets(
        'native QQ daily artwork and podcast episode navigation fit $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final catalog = _Catalog(FakeQqDiscoveryClient());
      Widget app(Widget child) => ScreenUtilInit(
          designSize: const Size(750, 1334),
          builder: (_, __) =>
              MaterialApp(theme: AppTheme.light, home: Scaffold(body: child)));
      await tester.pumpWidget(app(QqDailyView(discovery: catalog)));
      await tester.pumpAndSettle();
      expect(find.text('节目'), findsOneWidget);
      await tester.pumpWidget(app(QqPodcastsView(discovery: catalog)));
      await tester.pumpAndSettle();
      expect(find.text('真实QQ播客'), findsOneWidget);
      await tester.tap(find.text('真实QQ播客'));
      await tester.pumpAndSettle();
      expect(find.byType(QqPodcastEpisodesView), findsOneWidget);
      expect(find.text('节目'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.qq.dispose();
    });
  }
}
