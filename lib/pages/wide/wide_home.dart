// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../common/display_mode.dart';
import '../home/home_controller.dart';
import 'remote_button.dart';
import 'wide_catalog.dart';
import 'wide_playback.dart';
import 'wide_artwork.dart';
import 'wide_player.dart';

enum WideSection {
  recommended,
  playlists,
  search,
  local,
  queue,
  account,
  settings
}

class WideHome extends StatefulWidget {
  const WideHome(
      {super.key, this.catalog, this.playback, this.tv = DisplayMode.isTv});
  final WideCatalog? catalog;
  final WidePlayback? playback;
  final bool tv;

  @override
  State<WideHome> createState() => _WideHomeState();
}

class _WideHistory {
  _WideHistory(this.title, this.page, this.offset, this.focusId, this.loader);
  final String title;
  final WidePage page;
  final double offset;
  final String focusId;
  final Future<WidePage> Function(int) loader;
}

class _WideHomeState extends State<WideHome> {
  late final WideCatalog _catalog;
  late final WidePlayback _playback;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _nodes = <String, FocusNode>{};
  final _history = <_WideHistory>[];
  WideSection _section = WideSection.recommended;
  WidePage _page = const WidePage();
  String _title = '推荐歌单';
  String? _error;
  String? _account;
  bool _busy = false;
  bool _fullPlayer = false;
  bool _mediaBusy = false;
  int _request = 0;
  late Future<WidePage> Function(int) _loader;

  FocusNode _node(String id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: id));

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog ?? BujuanWideCatalog();
    _playback = widget.playback ?? WidePlayback.connect(Home.to);
    _playback.addListener(_queueChanged);
    _loader = (_) => _catalog.recommendations();
    _load();
    _refreshAccount();
  }

  Future<void> _refreshAccount() async {
    try {
      final name =
          await _catalog.refreshAccount().timeout(const Duration(seconds: 15));
      if (mounted) setState(() => _account = name);
    } catch (_) {
      /* Browsing and local playback do not require account refresh. */
    }
  }

  String _lastSong = '';
  List<MediaItem> _lastQueue = const [];
  void _queueChanged() {
    final data = _playback.value;
    final changed = data.song.id != _lastSong ||
        _section == WideSection.queue && !listEquals(data.queue, _lastQueue);
    _lastSong = data.song.id;
    _lastQueue = data.queue;
    if (changed && mounted) setState(() {});
  }

  Future<void> _load({bool append = false}) async {
    if (append && _busy) return;
    final request = ++_request;
    final offset = append ? _page.songs.length + _page.playlists.length : 0;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _loader(offset).timeout(const Duration(seconds: 20));
      if (!mounted || request != _request) return;
      setState(() {
        _page = append
            ? WidePage(
                songs: [..._page.songs, ...result.songs],
                playlists: [..._page.playlists, ...result.playlists],
                hasMore: result.hasMore,
              )
            : result;
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _error = error is StateError
              ? error.message.toString()
              : '暂时无法加载，请检查网络后重试';
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  void _select(WideSection section) {
    ++_request;
    setState(() {
      _section = section;
      _history.clear();
      _page = const WidePage();
      _busy = false;
      _error = null;
      _fullPlayer = false;
      _title = _labels[section.index];
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    switch (section) {
      case WideSection.recommended:
        _loader = (_) => _catalog.recommendations();
        _load();
        break;
      case WideSection.playlists:
        _loader = (offset) => _catalog.myPlaylists(offset: offset);
        _load();
        break;
      case WideSection.search:
        final keyword = _search.text.trim();
        _loader = (offset) => _catalog.search(keyword, offset: offset);
        if (_search.text.trim().isNotEmpty) _load();
        break;
      case WideSection.local:
        _loader = (_) => _catalog.localSongs();
        _load();
        break;
      case WideSection.queue:
      case WideSection.account:
      case WideSection.settings:
        break;
    }
  }

  Future<void> _openPlaylist(WidePlaylist list) async {
    _history.add(_WideHistory(
        _title,
        _page,
        _scroll.hasClients ? _scroll.offset : 0,
        'playlist:${list.id}',
        _loader));
    setState(() {
      _title = list.title;
      _page = const WidePage();
      _error = null;
    });
    _loader = (offset) => _catalog.playlistSongs(list.id, offset: offset);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _focus('back');
    await _load();
  }

  void _focus(String id) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _nodes[id]?.context != null) _nodes[id]!.requestFocus();
      });

  Future<bool> _back() async {
    if (_fullPlayer) {
      setState(() => _fullPlayer = false);
      _focus('open-player');
      return false;
    }
    if (_history.isNotEmpty) {
      final previous = _history.removeLast();
      ++_request;
      setState(() {
        _title = previous.title;
        _page = previous.page;
        _loader = previous.loader;
        _busy = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scroll.hasClients) {
          _scroll.jumpTo(
              previous.offset.clamp(0, _scroll.position.maxScrollExtent));
        }
        _focus(previous.focusId);
      });
      return false;
    }
    if (_section != WideSection.recommended) {
      _select(WideSection.recommended);
      _focus('nav:0');
      return false;
    }
    return true;
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) _notice('操作未完成，请检查网络或音频文件后重试');
    }
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  KeyEventResult _mediaKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final media = [
      LogicalKeyboardKey.mediaPlayPause,
      LogicalKeyboardKey.mediaPlay,
      LogicalKeyboardKey.mediaPause,
      LogicalKeyboardKey.mediaTrackNext,
      LogicalKeyboardKey.mediaTrackPrevious,
      LogicalKeyboardKey.mediaFastForward,
      LogicalKeyboardKey.mediaRewind
    ];
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (event is KeyDownEvent) {
        unawaited(_back().then((exit) {
          if (exit) SystemNavigator.pop();
        }));
      }
      return KeyEventResult.handled;
    }
    if (!media.contains(key)) return KeyEventResult.ignored;
    if (event is! KeyDownEvent || _mediaBusy) return KeyEventResult.handled;
    Future<void> action() async {
      if (key == LogicalKeyboardKey.mediaTrackNext) {
        await _playback.next();
      } else if (key == LogicalKeyboardKey.mediaTrackPrevious) {
        await _playback.previous();
      } else if (key == LogicalKeyboardKey.mediaFastForward ||
          key == LogicalKeyboardKey.mediaRewind) {
        final seconds = key == LogicalKeyboardKey.mediaFastForward ? 10 : -10;
        await _playback.seek(clampSeek(
            _playback.value.position + Duration(seconds: seconds),
            _playback.value.song.duration));
      } else if (key == LogicalKeyboardKey.mediaPlayPause ||
          key == LogicalKeyboardKey.mediaPlay && !_playback.value.playing ||
          key == LogicalKeyboardKey.mediaPause && _playback.value.playing) {
        await _playback.toggle();
      }
    }

    _mediaBusy = true;
    unawaited(_perform(action).whenComplete(() => _mediaBusy = false));
    return KeyEventResult.handled;
  }

  static const _labels = ['推荐歌单', '我的歌单', '搜索', '本地音乐', '播放队列', '账号', '设置'];
  static const _icons = [
    Icons.explore_outlined,
    Icons.library_music_outlined,
    Icons.search,
    Icons.folder_open,
    Icons.queue_music,
    Icons.person_outline,
    Icons.settings_outlined
  ];

  @override
  Widget build(BuildContext context) => Theme(
        data: wideTheme(),
        child: RemoteInputScope(
            child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _mediaKey,
                child: WillPopScope(
                    onWillPop: _back,
                    child: Scaffold(
                      body: SafeArea(
                          child: LayoutBuilder(builder: (context, constraints) {
                        final compact = constraints.maxWidth < 760 ||
                            constraints.maxHeight < 410;
                        final margin = widget.tv && !compact ? 20.0 : 10.0;
                        return Padding(
                            padding: EdgeInsets.all(margin),
                            child: Column(children: [
                              Row(children: [
                                const Icon(Icons.music_note, color: wideAccent),
                                const SizedBox(width: 8),
                                Text(widget.tv ? 'BuJuan TV' : '不倦 BuJuan',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                const Spacer(),
                                if (compact)
                                  RemoteButton(
                                      key: const ValueKey('open-player'),
                                      focusNode: _node('open-player'),
                                      onPressed: () => setState(
                                          () => _fullPlayer = !_fullPlayer),
                                      child: Text(
                                          _fullPlayer ? '返回列表' : '播放 / 歌词')),
                              ]),
                              const SizedBox(height: 8),
                              Expanded(
                                  child: compact && _fullPlayer
                                      ? WidePlayer(
                                          playback: _playback,
                                          perform: _perform)
                                      : Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                              SizedBox(
                                                  width: compact ? 76 : 106,
                                                  child: _navigation()),
                                              const SizedBox(width: 10),
                                              Expanded(child: _content()),
                                              if (!compact) ...[
                                                const SizedBox(width: 16),
                                                SizedBox(
                                                    width: (constraints
                                                                .maxWidth *
                                                            .36)
                                                        .clamp(270.0, 440.0),
                                                    child: WidePlayer(
                                                        playback: _playback,
                                                        perform: _perform)),
                                              ],
                                            ])),
                              if (compact && !_fullPlayer) ...[
                                const SizedBox(height: 6),
                                WideMiniPlayer(
                                    playback: _playback, perform: _perform),
                              ],
                            ]));
                      })),
                    )))),
      );

  Widget _navigation() => ListView(children: [
        for (final section in WideSection.values)
          Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: RemoteButton(
                key: ValueKey('nav:${section.index}'),
                focusNode: _node('nav:${section.index}'),
                autofocus: section == WideSection.recommended,
                selected: _section == section,
                onPressed: () => _select(section),
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Column(children: [
                  Icon(_icons[section.index], size: 24),
                  const SizedBox(height: 5),
                  Text(_labels[section.index],
                      style: const TextStyle(fontSize: 13))
                ]),
              )),
      ]);

  Widget _content() =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (_history.isNotEmpty)
            RemoteButton(
                focusNode: _node('back'),
                onPressed: () async {
                  await _back();
                },
                child: const Icon(Icons.arrow_back)),
          Expanded(
              child: Text(_title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold))),
          if ([
            WideSection.recommended,
            WideSection.playlists,
            WideSection.local
          ].contains(_section))
            RemoteButton(
                onPressed: () => _load(), child: const Icon(Icons.refresh)),
        ]),
        if (_section == WideSection.search)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Expanded(
                    child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                      hintText: '歌名或歌手', border: OutlineInputBorder()),
                  onSubmitted: (_) => _submitSearch(),
                )),
                const SizedBox(width: 8),
                RemoteButton(onPressed: _submitSearch, child: const Text('搜索'))
              ])),
        Expanded(
            child: _section == WideSection.account
                ? _accountView()
                : _section == WideSection.settings
                    ? _settingsView()
                    : _section == WideSection.queue
                        ? _songs(_playback.value.queue, queue: true)
                        : _library()),
      ]);

  void _submitSearch() {
    if (_search.text.trim().isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final keyword = _search.text.trim();
    _loader = (offset) => _catalog.search(keyword, offset: offset);
    _page = const WidePage();
    _history.clear();
    _load();
    _focus('nav:2');
  }

  Widget _library() {
    if (_busy && _page.songs.isEmpty && _page.playlists.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: wideAccent));
    }
    if (_error != null && _page.songs.isEmpty && _page.playlists.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        RemoteButton(onPressed: () => _load(), child: const Text('重试')),
      ]));
    }
    if (_page.songs.isNotEmpty) return _songs(_page.songs);
    if (_page.playlists.isNotEmpty) {
      return ListView.builder(
          controller: _scroll,
          itemCount: _page.playlists.length + (_page.hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == _page.playlists.length) return _loadMore();
            final list = _page.playlists[i];
            return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: RemoteButton(
                  key: ValueKey('playlist:${list.id}'),
                  focusNode: _node('playlist:${list.id}'),
                  onPressed: () => _openPlaylist(list),
                  child: Row(children: [
                    WideArtwork(url: list.artwork, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(list.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.chevron_right)
                  ]),
                ));
          });
    }
    return const Center(child: Text('暂无内容'));
  }

  Widget _loadMore() => RemoteButton(
        onPressed: () => _load(append: true),
        child: Text(_busy
            ? '加载中…'
            : _error == null
                ? '加载更多'
                : '加载失败，点击重试'),
      );

  Widget _songs(List<MediaItem> songs, {bool queue = false}) {
    if (songs.isEmpty) return const Center(child: Text('暂无歌曲'));
    return ListView.builder(
        controller: _scroll,
        itemCount: songs.length + (!queue && _page.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == songs.length) return _loadMore();
          final song = songs[i];
          return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                    child: RemoteButton(
                        key: ValueKey('song:${song.id}'),
                        focusNode: _node('song:${song.id}'),
                        selected: _playback.value.song.id == song.id,
                        onPressed: () => _perform(() => queue
                            ? _playback.playQueueIndex(i)
                            : _playback.playSongs(songs, i)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(song.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text(song.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white60)),
                            ]))),
                RemoteButton(
                    key: ValueKey('more:${song.id}'),
                    onPressed: () => _songMenu(song),
                    child: const Icon(Icons.more_horiz)),
              ]));
        });
  }

  Future<void> _songMenu(MediaItem song) async {
    await showDialog<void>(
        context: context,
        builder: (context) => Theme(
            data: wideTheme(),
            child: RemoteInputScope(
              child: AlertDialog(
                  title: Text(song.title, maxLines: 2),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    RemoteButton(
                        autofocus: true,
                        onPressed: () async {
                          Navigator.pop(context);
                          await _perform(() => _playback.playNext(song));
                        },
                        child: const Text('下一首播放')),
                    RemoteButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭')),
                  ])),
            )));
  }

  Widget _accountView() => SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        Text(_account == null ? '扫码登录网易云音乐' : '已登录：$_account'),
        const SizedBox(height: 16),
        RemoteButton(
            onPressed: _login,
            child: Text(_account == null ? '显示登录二维码' : '切换账号')),
        const SizedBox(height: 8),
        if (_account != null)
          RemoteButton(
              onPressed: () => _perform(() async {
                    await _catalog.logout();
                    if (mounted) setState(() => _account = null);
                  }),
              child: const Text('退出登录')),
      ]));

  Future<void> _login() async {
    final success = await showDialog<bool>(
        context: context,
        builder: (context) => WideLoginDialog(catalog: _catalog));
    if (success == true) {
      await _refreshAccount();
    }
  }

  Widget _settingsView() => SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        const Text('方向键移动焦点，确定键执行操作。\n焦点在进度条时，左右键快退 / 快进。\n返回键先返回列表，再回首页。',
            style: TextStyle(height: 1.8)),
        const SizedBox(height: 16),
        RemoteButton(
            onPressed: () => _perform(_playback.favorite),
            child: const Text('收藏 / 取消收藏当前歌曲')),
        const SizedBox(height: 12),
        RemoteButton(
            onPressed: () {
              _playback.repeat();
            },
            child: const Text('切换循环模式')),
        const SizedBox(height: 20),
        const Text(
            '横屏与 TV 试用版 · 2.0.5 / 2040\n原作者：2697a / sixbugs\n基于 MIT 许可的 BuJuan 社区修复版',
            style: TextStyle(fontSize: 12, color: Colors.white60, height: 1.6)),
      ]));

  @override
  void dispose() {
    ++_request;
    _playback.removeListener(_queueChanged);
    if (widget.playback == null) _playback.dispose();
    _search.dispose();
    _scroll.dispose();
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }
}

class WideLoginDialog extends StatefulWidget {
  const WideLoginDialog({super.key, required this.catalog});
  final WideCatalog catalog;
  @override
  State<WideLoginDialog> createState() => _WideLoginDialogState();
}

class _WideLoginDialogState extends State<WideLoginDialog> {
  WideQr? _qr;
  String _status = '正在获取二维码…';
  Timer? _timer;
  int _request = 0;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    _timer?.cancel();
    setState(() {
      _qr = null;
      _status = '正在获取二维码…';
    });
    try {
      final qr =
          await widget.catalog.loginQr().timeout(const Duration(seconds: 15));
      if (!mounted || request != _request) return;
      setState(() {
        _qr = qr;
        _status = '使用网易云音乐 App 扫码登录';
      });
      _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (_checking || !mounted) return;
        _checking = true;
        try {
          final code = await qr.check().timeout(const Duration(seconds: 10));
          if (!mounted || request != _request) return;
          if (code == 803) {
            _timer?.cancel();
            Navigator.pop(context, true);
          } else if (code == 800) {
            _timer?.cancel();
            setState(() => _status = '二维码过期，请刷新');
          } else if (code == 802) {
            setState(() => _status = '请在手机上确认登录');
          }
        } catch (_) {
          if (mounted && request == _request) {
            setState(() => _status = '连接失败，可刷新二维码重试');
          }
        } finally {
          _checking = false;
        }
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _status = '获取失败，请刷新重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final qrSize = math.max(
        80.0, math.min(200.0, MediaQuery.sizeOf(context).height - 240));
    return Theme(
        data: wideTheme(),
        child: RemoteInputScope(
            child: AlertDialog(
          title: const Text('网易云音乐登录'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_qr != null)
              SizedBox(
                  width: qrSize + 12,
                  height: qrSize + 12,
                  child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(6),
                      child: QrImageView(data: _qr!.url, size: qrSize))),
            const SizedBox(height: 10),
            Text(_status),
          ])),
          actions: [
            RemoteButton(
                autofocus: true,
                onPressed: _refresh,
                child: const Text('刷新二维码')),
            RemoteButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('关闭')),
          ],
        )));
  }

  @override
  void dispose() {
    ++_request;
    _timer?.cancel();
    super.dispose();
  }
}
