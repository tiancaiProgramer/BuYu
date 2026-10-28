// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

/// NetEase cloud storage requires its own account, even when QQ is signed in.
class CloudAccountGate extends StatefulWidget {
  const CloudAccountGate(
      {super.key,
      required this.loggedIn,
      this.accountId,
      required this.onLogin,
      required this.contentBuilder});
  final bool loggedIn;
  final Object? accountId;
  final Future<void> Function() onLogin;
  final Widget Function(BuildContext, WidgetBuilder) contentBuilder;
  @override
  State<CloudAccountGate> createState() => _CloudAccountGateState();
}

class _CloudAccountGateState extends State<CloudAccountGate> {
  int _generation = 0;
  bool _opening = false;
  Future<void> _login() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onLogin();
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _generation++;
        });
      }
    }
  }

  Widget _prompt(BuildContext context) => Center(
      child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(TablerIcons.cloud, size: 48),
            const SizedBox(height: 12),
            TextButton(
                onPressed: _opening ? null : _login,
                child: const Text('请登录账号')),
            const SizedBox(height: 8),
            const Text('云盘需要登录网易云音乐账号', textAlign: TextAlign.center),
          ])));

  @override
  Widget build(BuildContext context) => widget.loggedIn
      ? KeyedSubtree(
          key: ValueKey('${widget.accountId}:$_generation'),
          child: widget.contentBuilder(context, _prompt))
      : _prompt(context);
}
