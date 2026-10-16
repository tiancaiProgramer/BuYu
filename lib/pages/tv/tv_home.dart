// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../common/display_mode.dart';
import '../home/home_controller.dart';
import 'tv_player.dart';
import '../wide/remote_button.dart';
import '../wide/wide_catalog.dart';
import '../wide/wide_playback.dart';
import '../wide/wide_home.dart' show WideLoginDialog;
import '../wide/wide_player.dart';

enum TvSection {
  recommended,
  playlists,
  search,
  local,
  queue,
  account,
  settings
}

class TvHome extends StatefulWidget {
  const TvHome(
      {super.key, this.catalog, this.playback, this.tv = DisplayMode.isTv});
  final WideCatalog? catalog;
  final WidePlayback? playback;
  final bool tv;

  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHistory {
  _TvHistory(this.title, this.page, this.offset, this.focusId, this.loader);
  final String title;
  final WidePage page;
  final double offset;
  final String focusId;
  final Future<WidePage> Function(int) loader;
}

class _TvHomeState extends State<TvHome> {
  late final WideCatalog _catalog;
  late final WidePlayback _playback;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _nodes = <String, FocusNode>{};
  final _history = <_TvHistory>[];
  TvSection _section = TvSection.recommended;
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
    _lastSong = _playback.value.song.id;
    _lastQueue = _playback.value.queue;
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
        _section == TvSection.queue && !listEquals(data.queue, _lastQueue);
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

  void _select(TvSection section) {
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
      case TvSection.recommended:
        _loader = (_) => _catalog.recommendations();
        _load();
        break;
      case TvSection.playlists:
        _loader = (offset) => _catalog.myPlaylists(offset: offset);
        _load();
        break;
      case TvSection.search:
        final keyword = _search.text.trim();
        _loader = (offset) => _catalog.search(keyword, offset: offset);
        if (_search.text.trim().isNotEmpty) _load();
        break;
      case TvSection.local:
        _loader = (_) => _catalog.localSongs();
        _load();
        break;
      case TvSection.queue:
      case TvSection.account:
      case TvSection.settings:
        break;
    }
  }

  Future<void> _openPlaylist(WidePlaylist list) async {
    _history.add(_TvHistory(
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
    if (_section != TvSection.recommended) {
      _select(TvSection.recommended);
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
    TablerIcons.compass,
    TablerIcons.playlist,
    TablerIcons.search,
    TablerIcons.file_music,
    TablerIcons.list,
    TablerIcons.user,
    TablerIcons.settings
  ];

  @override
  Widget build(BuildContext context) => Theme(
      data: ThemeData.dark(useMaterial3: false).copyWith(
        primaryColor: const Color(0xffe56260),
        scaffoldBackgroundColor: const Color(0xff17191d),
        colorScheme: const ColorScheme.dark(primary: Color(0xffe56260)),
      ),
      child: RemoteFocusStyle(
          color: Colors.white,
          fill: const Color(0xff383b40),
          selection: const Color(0xff2c2e33),
          child: RemoteInputScope(
              child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _mediaKey,
                  child: WillPopScope(
                      onWillPop: _back,
                      child: Scaffold(
                          body: SafeArea(
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 28, vertical: 18),
                                  child: _fullPlayer
                                      ? TvPlayer(
                                          playback: _playback,
                                          perform: _perform,
                                          onBack: () {
                                            _back();
                                          })
                                      : Column(children: [
                                          Row(children: [
                                            const Icon(TablerIcons.music,
                                                color: Color(0xffe56260)),
                                            const SizedBox(width: 10),
                                            const Text('BuJuan TV',
                                                style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            const SizedBox(width: 24),
                                            Expanded(
                                                child: SingleChildScrollView(
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: _navigation())),
                                          ]),
                                          const SizedBox(height: 24),
                                          Expanded(child: _content()),
                                          const SizedBox(height: 14),
                                          _miniPlayer(),
                                        ])))))))));

  Widget _navigation() => Row(children: [
        for (final section in TvSection.values)
          Padding(
              padding: const EdgeInsets.only(right: 6),
              child: RemoteButton(
                  key: ValueKey('nav:${section.index}'),
                  focusNode: _node('nav:${section.index}'),
                  autofocus: section == TvSection.recommended,
                  selected: _section == section,
                  onPressed: () => _select(section),
                  child: Row(children: [
                    Icon(_icons[section.index], size: 22),
                    const SizedBox(width: 6),
                    Text(_labels[section.index],
                        style: const TextStyle(fontSize: 16))
                  ]))),
      ]);

  Widget _miniPlayer() => Row(children: [
        Expanded(
            child: RemoteButton(
                key: const ValueKey('open-player'),
                focusNode: _node('open-player'),
                onPressed: () => setState(() => _fullPlayer = true),
                child: PlaybackSlice(
                    playback: _playback,
                    select: (d) => d.song,
                    builder: (_, data) => Row(children: [
                          TvArtwork(
                              url: data.song.extras?['image'] as String? ?? '',
                              size: 44),
                          const SizedBox(width: 14),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(data.song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                Text(data.song.artist ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 13)),
                              ])),
                          const Icon(TablerIcons.quote),
                        ])))),
        const SizedBox(width: 18),
        TvControls(playback: _playback, perform: _perform, mini: true),
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
          if ([TvSection.recommended, TvSection.playlists, TvSection.local]
              .contains(_section))
            RemoteButton(
                onPressed: () => _load(), child: const Icon(Icons.refresh)),
        ]),
        if (_section == TvSection.search)
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
            child: _section == TvSection.account
                ? _accountView()
                : _section == TvSection.settings
                    ? _settingsView()
                    : _section == TvSection.queue
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
      return const Center(
          child: CircularProgressIndicator(color: Color(0xffe56260)));
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
      return LayoutBuilder(builder: (_, constraints) {
        final columns = (constraints.maxWidth / 215).floor().clamp(2, 6);
        return GridView.builder(
            controller: _scroll,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: .82),
            itemCount: _page.playlists.length + (_page.hasMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == _page.playlists.length) return _loadMore();
              final list = _page.playlists[i];
              return RemoteButton(
                  key: ValueKey('playlist:${list.id}'),
                  focusNode: _node('playlist:${list.id}'),
                  onPressed: () => _openPlaylist(list),
                  padding: const EdgeInsets.all(8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                            child: LayoutBuilder(
                                builder: (_, c) => Center(
                                    child: TvArtwork(
                                        url: list.artwork,
                                        size: c.maxWidth < c.maxHeight
                                            ? c.maxWidth
                                            : c.maxHeight)))),
                        const SizedBox(height: 10),
                        Text(list.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17)),
                      ]));
            });
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
            data: Theme.of(context),
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
            'TV 试用版 · 2.0.5 / 2042\n原作者：2697a / sixbugs\n基于 MIT 许可的 BuJuan 社区修复版',
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
