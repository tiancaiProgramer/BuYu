// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../common/music/music_source.dart';
import '../../widget/buyu_components.dart';
import '../home/home_controller.dart';
import '../login/login.dart';
import 'source_access.dart';

/// A shared platform selector for discovery, daily songs and podcasts.
class DiscoverySources extends StatefulWidget {
  const DiscoverySources(
      {super.key,
      required this.id,
      required this.netease,
      required this.qq,
      this.publicSources = const {},
      this.statusReader});
  final String id;
  final WidgetBuilder netease, qq;
  final Set<MusicSource> publicSources;
  final bool Function(MusicSource)? statusReader;
  @override
  State<DiscoverySources> createState() => _DiscoverySourcesState();
}

class _DiscoverySourcesState extends State<DiscoverySources> {
  MusicSource _source = MusicSource.netease;
  late final SourceAccess _access;
  bool signedIn(MusicSource source) => _access.signedIn(source);
  bool available(MusicSource source) =>
      widget.publicSources.contains(source) || signedIn(source);
  void accountsChanged() {
    if (!mounted) return;
    setState(() {
      final sources = _access.sources;
      if (!sources.contains(_source) && sources.isNotEmpty) {
        _source = sources.first;
      } else if (!available(_source) && signedIn(other)) {
        _source = other;
      }
    });
  }

  MusicSource get other =>
      _source == MusicSource.qq ? MusicSource.netease : MusicSource.qq;
  @override
  void initState() {
    super.initState();
    _access = SourceAccess(statusReader: widget.statusReader);
    if (Get.isRegistered<Home>()) {
      final saved = Home.to.box.get('DISCOVERY_SOURCE_${widget.id}');
      _source = MusicSource.values.firstWhere(
          (s) => s.name == saved && available(s) && _access.sources.contains(s),
          orElse: () =>
              signedIn(MusicSource.netease) || !signedIn(MusicSource.qq)
                  ? MusicSource.netease
                  : MusicSource.qq);
    } else if (signedIn(MusicSource.qq) && !signedIn(MusicSource.netease)) {
      _source = MusicSource.qq;
    }
    _access.addListener(accountsChanged);
  }

  @override
  void dispose() {
    _access.removeListener(accountsChanged);
    _access.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (_access.sources.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(spacing: 8, children: [
                for (final source in _access.sources)
                  BuYuChoiceChip(
                      key: ValueKey('discovery-source:${source.name}'),
                      label: Text(source.label),
                      selected: _source == source,
                      onSelected: (_) {
                        setState(() => _source = source);
                        if (Get.isRegistered<Home>())
                          Home.to.box.put(
                              'DISCOVERY_SOURCE_${widget.id}', source.name);
                      })
              ])),
        Expanded(
            child: KeyedSubtree(
                key: ValueKey(
                    '${widget.id}:${_source.name}:${signedIn(_source)}:${_access.account(_source)}'),
                child: _access.sources.isEmpty
                    ? Center(
                        child: TextButton(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => const LoginViewPage()));
                              accountsChanged();
                            },
                            child: const Text('暂无已登录的平台，请先登录音乐账号')))
                    : available(_source)
                        ? (_source == MusicSource.qq
                            ? widget.qq(context)
                            : widget.netease(context))
                        : Center(
                            child: TextButton(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                          builder: (_) => LoginViewPage(
                                              initialSource: _source)));
                                  accountsChanged();
                                },
                                child: Text('请登录${_source.label}账号'))))),
      ]);
}
