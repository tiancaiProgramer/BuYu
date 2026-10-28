// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:bujuan/common/bujuan_audio_handler.dart';
import 'package:bujuan/common/music/music_source.dart';
import 'package:bujuan/common/music/qq_discovery.dart';
import 'package:bujuan/common/music/qq_music.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/pages/music/discovery_sources.dart';
import 'package:bujuan/pages/music/qq_recommendations_view.dart';
import 'package:bujuan/pages/index/main_view.dart';
import 'package:bujuan/pages/index/index_controller.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/music/mixed_library_view.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'download_preferences_test.dart' show MemoryBox;
import 'phone_rotation_test.dart' show OfflineHome;
import 'playback_regression_test.dart' show FakePlayer;

class RecommendationClient extends QqMusic {
  String accountId = '';
  Future<Map> Function(Map<String, dynamic>)? respond;
  SourcePlaylist? openedPlaylist;
  @override
  Future<List<MediaItem>> playlistSongs(SourcePlaylist list,
      {int page = 1}) async {
    openedPlaylist = list;
    return [
      QqMusic.song({'mid': 'qq-track', 'id': 12, 'title': 'QQ推荐歌单里的歌曲'})
    ];
  }

  @override
  String get account => accountId;
  @override
  Future<void> restore() async {}
  @override
  Future<Map> rpc(String module, String method, Map<String, dynamic> param,
      {CancelToken? cancelToken,
      bool auth = false,
      String? expectedAccount}) async {
    expect(module, 'music.playlist.PlaylistSquare');
    expect(method, 'GetRecommendFeed');
    expect(auth, false);
    expect(expectedAccount, accountId);
    expect(param['Size'], 20);
    return await respond!(param);
  }
}

class RecommendationHome extends OfflineHome {
  List<MediaItem>? played;
  @override
  Future<void> playByIndex(int index, String queueTitle,
      {List<MediaItem>? mediaItem}) async {
    played = mediaItem;
  }
}

class StaticIndex extends IndexController {
  StaticIndex() {
    loading.value = false;
  }
  @override
  void onReady() {}
}

Map card(String id, {String title = '推荐歌单'}) => {
      'Playlist': {
        'basic': {
          'tid': id,
          'title': title,
          'dirid': 29,
          'song_cnt': 52,
          'cover': {'medium_url': '//example.invalid/cover.jpg'}
        }
      }
    };

SourcePlaylist playlist(String id) => SourcePlaylist(
    source: MusicSource.qq, id: id, directory: '29', name: '歌单$id', count: 52);

class RecommendationCatalog extends QqDiscovery {
  RecommendationCatalog() : super(RecommendationClient());
  final offsets = <int>[];
  final tokens = <CancelToken>[];
  Future<QqPlaylistPage> Function(int)? respond;
  @override
  Future<QqPlaylistPage> recommendedPlaylists(
      {int offset = 0, CancelToken? cancelToken}) {
    offsets.add(offset);
    tokens.add(cancelToken!);
    return respond!(offset);
  }
}

Widget app(Widget child, {double textScale = 1}) => MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!),
    home: Scaffold(body: child));

void main() {
  testWidgets(
      'home source choice survives rotation and reopen; QQ cards open read-only QQ details and play QQ tracks',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final box = MemoryBox();
    final audio = (await tester.runAsync(() async => BujuanAudioHandler(
        player: FakePlayer(), box: box, restoreQueue: false)))!;
    final qq = RecommendationClient();
    qq.respond = (_) async => {
          'List': [card('7700643924', title: 'QQ官方推荐歌单')],
          'HasMore': false
        };
    GetIt.I.registerSingleton<Box>(box);
    GetIt.I.registerSingleton<BujuanAudioHandler>(audio);
    GetIt.I.registerSingleton<ZoomDrawerController>(ZoomDrawerController());
    GetIt.I.registerSingleton<QqMusic>(qq);
    late RecommendationHome home;
    Widget mainApp(Key key) => ScreenUtilInit(
        designSize: const Size(750, 1334),
        builder: (_, __) {
          if (!Get.isRegistered<Home>()) {
            home = RecommendationHome();
            Get.put<Home>(home);
            Get.put<IndexController>(StaticIndex());
          }
          return GetMaterialApp(
              theme: AppTheme.light, home: MainView(key: key));
        });
    await tester.pumpWidget(mainApp(const ValueKey('first')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discovery-source:qq')));
    await tester.pumpAndSettle();
    expect(find.text('QQ官方推荐歌单'), findsOneWidget);
    expect(box.get('DISCOVERY_SOURCE_home'), 'qq');
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(find.text('QQ官方推荐歌单'), findsOneWidget);
    await tester.tap(find.text('QQ官方推荐歌单'));
    await tester.pumpAndSettle();
    expect(find.byType(MixedLibraryView), findsOneWidget);
    expect(qq.openedPlaylist!.id, '7700643924');
    expect(find.byTooltip('从此列表移除'), findsNothing);
    await tester.tap(find.text('QQ推荐歌单里的歌曲'));
    await tester.pumpAndSettle();
    expect(home.played!.single.id, 'qq:qq-track');
    Get.back<void>();
    await tester.pumpAndSettle();
    await tester.pumpWidget(mainApp(const ValueKey('reopened')));
    await tester.pumpAndSettle();
    expect(find.text('QQ官方推荐歌单'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    await GetIt.I.reset();
    qq.dispose();
    await tester.runAsync(audio.dispose);
  });

  test(
      'public feed keeps QQ IDs, covers and directory, paginates raw rows and removes duplicates',
      () async {
    final qq = RecommendationClient();
    qq.respond = (param) async {
      expect(param['From'], 20);
      return {
        'List': [
          card('7700643924', title: '歌单 &amp; 推荐'),
          card('7700643924'),
          card('0'),
          {'unrelated': true}
        ],
        'HasMore': true,
        'FromLimit': 400
      };
    };
    final page = await QqDiscovery(qq).recommendedPlaylists(offset: 20);
    expect(page.nextOffset, 24);
    expect(page.hasMore, true);
    final list = page.playlists.single;
    expect(list.id, '7700643924');
    expect(list.source, MusicSource.qq);
    expect(list.directory, '29');
    expect(list.name, '歌单 & 推荐');
    expect(list.image, 'https://example.invalid/cover.jpg');
    expect(list.count, 52);
    qq.dispose();
  });

  test(
      'empty feed ends pagination, malformed feed fails, upstream range cap stops loading',
      () async {
    final qq = RecommendationClient();
    final api = QqDiscovery(qq);
    qq.respond = (_) async => {'List': [], 'HasMore': true};
    expect((await api.recommendedPlaylists()).hasMore, false);
    for (final data in [
      {},
      {
        'List': [card('0')]
      }
    ]) {
      qq.respond = (_) async => data;
      await expectLater(
          api.recommendedPlaylists(), throwsA(isA<MusicServiceError>()));
    }
    qq.respond = (_) async => {
          'List': [card('1')],
          'HasMore': true,
          'FromLimit': 400
        };
    expect((await api.recommendedPlaylists(offset: 399)).hasMore, false);
    qq.dispose();
  });

  test('late recommendations from a previous account are rejected', () async {
    final qq = RecommendationClient()..accountId = '123';
    qq.respond = (_) async {
      qq.accountId = '456';
      return {
        'List': [card('1')],
        'HasMore': false
      };
    };
    await expectLater(QqDiscovery(qq).recommendedPlaylists(),
        throwsA(isA<MusicServiceError>()));
    qq.dispose();
  });

  test('legacy HTTP covers and empty preferred sizes use a valid HTTPS cover',
      () async {
    final qq = RecommendationClient();
    final first = card('1'), second = card('2');
    (first['Playlist']['basic'] as Map)['cover'] = {
      'medium_url': 'http://qpic.y.qq.com/cover.jpg'
    };
    (second['Playlist']['basic'] as Map)['cover'] = {
      'medium_url': '',
      'default_url': '//y.gtimg.cn/cover.jpg'
    };
    qq.respond = (_) async => {
          'List': [first, second],
          'HasMore': false
        };
    final page = await QqDiscovery(qq).recommendedPlaylists();
    expect(page.playlists.map((p) => p.image),
        ['https://qpic.y.qq.com/cover.jpg', 'https://y.gtimg.cn/cover.jpg']);
    qq.dispose();
  });

  testWidgets(
      'anonymous discovery can switch both sources without the daily login gate',
      (tester) async {
    var qqLoads = 0;
    await tester.pumpWidget(app(DiscoverySources(
        id: 'public-home',
        publicSources: const {MusicSource.netease, MusicSource.qq},
        statusReader: (_) => false,
        netease: (_) => const Text('网易云歌单推荐'),
        qq: (_) {
          qqLoads++;
          return const Text('QQ歌单推荐');
        })));
    await tester.pumpAndSettle();
    expect(find.text('网易云歌单推荐'), findsOneWidget);
    expect(qqLoads, 0);
    await tester.tap(find.byKey(const ValueKey('discovery-source:qq')));
    await tester.pumpAndSettle();
    expect(find.text('QQ歌单推荐'), findsOneWidget);
    expect(find.text('请登录QQ音乐账号'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await GetIt.I.reset();
  });

  testWidgets(
      'failed pagination keeps cards and retries same offset, refresh resets feed',
      (tester) async {
    final api = RecommendationCatalog();
    var failures = 0;
    api.respond = (offset) async {
      if (offset == 0)
        return QqPlaylistPage([playlist('1')], nextOffset: 20, hasMore: true);
      if (failures++ == 0) throw const MusicServiceError('临时连接失败');
      return QqPlaylistPage([playlist('1'), playlist('2')],
          nextOffset: 40, hasMore: false);
    };
    SourcePlaylist? opened;
    await tester.pumpWidget(app(QqRecommendationsView(
        discovery: api, onOpenPlaylist: (p) => opened = p)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(find.text('歌单1'), findsOneWidget);
    expect(find.text('临时连接失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(api.offsets, [0, 20, 20]);
    expect(find.text('歌单1'), findsOneWidget);
    expect(find.text('歌单2'), findsOneWidget);
    await tester.tap(find.text('歌单2'));
    expect(opened!.id, '2');
    expect(opened!.source, MusicSource.qq);
    await tester.tap(find.byTooltip('刷新QQ推荐歌单'));
    await tester.pumpAndSettle();
    expect(api.offsets.last, 0);
    expect(find.text('歌单2'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    api.qq.dispose();
  });

  testWidgets('switching away cancels request and ignores late feed',
      (tester) async {
    final api = RecommendationCatalog();
    final pending = Completer<QqPlaylistPage>();
    api.respond = (_) => pending.future;
    await tester.pumpWidget(app(QqRecommendationsView(discovery: api)));
    await tester.pump();
    await tester.pumpWidget(app(const Text('网易云内容')));
    expect(api.tokens.single.isCancelled, true);
    pending.complete(
        QqPlaylistPage([playlist('old')], nextOffset: 20, hasMore: false));
    await tester.pumpAndSettle();
    expect(find.text('歌单old'), findsNothing);
    expect(tester.takeException(), isNull);
    api.qq.dispose();
  });

  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(640, 300),
    const Size(800, 1280)
  ]) {
    testWidgets(
        'QQ playlist cards and refresh fit portrait, landscape and tablet $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final api = RecommendationCatalog();
      api.respond = (_) async => QqPlaylistPage(
          [playlist('1'), playlist('2'), playlist('3')],
          nextOffset: 3, hasMore: false);
      await tester.pumpWidget(
          app(QqRecommendationsView(discovery: api), textScale: 1.3));
      await tester.pumpAndSettle();
      expect(find.text('歌单1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      api.qq.dispose();
    });
  }
}
