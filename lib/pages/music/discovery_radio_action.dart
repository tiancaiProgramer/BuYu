// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../../common/music/music_source.dart';
import '../../common/music/qq_music.dart';
import '../../widget/adaptive_option_sheet.dart';
import '../home/home_controller.dart';
import '../login/login.dart';
import '../user/user_controller.dart';

bool _openingRadio = false;
Future<void> openDiscoveryRadio(BuildContext context) async {
  if (_openingRadio) return;
  _openingRadio = true;
  try {
    final sources = [
      if (Home.to.loginStatus.value == LoginStatus.login) MusicSource.netease,
      if (QqMusic.instance.loggedIn) MusicSource.qq,
    ];
    if (sources.isEmpty) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const LoginViewPage()));
      return;
    }
    final source = sources.length == 1
        ? sources.single
        : await showModalBottomSheet<MusicSource>(
            context: context,
            isScrollControlled: true,
            builder: (sheet) =>
                AdaptiveOptionSheet(title: 'FM · 选择平台', children: [
                  for (final platform in sources)
                    ListTile(
                        leading: const Icon(TablerIcons.vinyl),
                        title: Text(platform.label),
                        subtitle:
                            Text(platform == MusicSource.qq ? '猜你喜欢' : '私人FM'),
                        onTap: () => Navigator.pop(sheet, platform)),
                ]));
    if (source == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('正在加载${source.label}FM…'),
        duration: const Duration(seconds: 2)));
    await Home.to.startSourceRadio(source);
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is MusicServiceError ? e.message : 'FM加载失败，请重试')));
  } finally {
    _openingRadio = false;
  }
}
