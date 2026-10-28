// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../common/music/music_source.dart';
import '../../common/music/qq_music.dart';
import '../../widget/buyu_components.dart';
import '../home/home_controller.dart';
import '../login/login.dart';
import '../user/user_controller.dart';

/// A shared platform selector inside the existing daily and podcast pages.
class DiscoverySources extends StatefulWidget {
  const DiscoverySources(
      {super.key,
      required this.id,
      required this.netease,
      required this.qq,
      this.statusReader});
  final String id;
  final WidgetBuilder netease, qq;
  final bool Function(MusicSource)? statusReader;
  @override
  State<DiscoverySources> createState() => _DiscoverySourcesState();
}

class _DiscoverySourcesState extends State<DiscoverySources> {
  MusicSource _source = MusicSource.netease;
  Worker? _worker;
  bool signedIn(MusicSource source) =>
      widget.statusReader?.call(source) ??
      (source == MusicSource.qq
          ? QqMusic.instance.loggedIn
          : Get.isRegistered<Home>() &&
              Home.to.loginStatus.value == LoginStatus.login);
  void accountsChanged() {
    if (!mounted) return;
    setState(() {
      if (!signedIn(_source) && signedIn(other)) _source = other;
    });
  }

  MusicSource get other =>
      _source == MusicSource.qq ? MusicSource.netease : MusicSource.qq;
  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<Home>()) {
      final saved = Home.to.box.get('DISCOVERY_SOURCE_${widget.id}');
      _source = MusicSource.values.firstWhere(
          (s) => s.name == saved && signedIn(s),
          orElse: () =>
              signedIn(MusicSource.netease) || !signedIn(MusicSource.qq)
                  ? MusicSource.netease
                  : MusicSource.qq);
      _worker = ever(Home.to.loginStatus, (_) => accountsChanged());
    } else if (signedIn(MusicSource.qq) && !signedIn(MusicSource.netease)) {
      _source = MusicSource.qq;
    }
    QqMusic.instance.addListener(accountsChanged);
  }

  @override
  void dispose() {
    _worker?.dispose();
    QqMusic.instance.removeListener(accountsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(spacing: 8, children: [
              for (final source in MusicSource.values)
                BuYuChoiceChip(
                    key: ValueKey('discovery-source:${source.name}'),
                    label: Text(source.label),
                    selected: _source == source,
                    onSelected: (_) {
                      setState(() => _source = source);
                      if (Get.isRegistered<Home>())
                        Home.to.box
                            .put('DISCOVERY_SOURCE_${widget.id}', source.name);
                    })
            ])),
        Expanded(
            child: KeyedSubtree(
                key: ValueKey(
                    '${widget.id}:${_source.name}:${signedIn(_source)}'),
                child: signedIn(_source)
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
