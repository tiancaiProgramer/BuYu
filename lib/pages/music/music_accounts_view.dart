import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../../widget/buyu_components.dart';
import '../../widget/adaptive_option_sheet.dart';
import '../../widget/simple_extended_image.dart';
// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import '../../common/music/qq_music.dart';
import 'library_actions.dart';
import '../../common/music/music_source.dart';
import '../../common/music/unified_library.dart';
import '../user/user_controller.dart';
import '../home/home_controller.dart';
import 'mixed_library_view.dart';
import '../login/login.dart';

class MusicAccountsView extends StatefulWidget {
  const MusicAccountsView({super.key});
  @override
  State<MusicAccountsView> createState() => _MusicAccountsViewState();
}

class _MusicAccountsViewState extends State<MusicAccountsView> {
  bool busy = false;
  String? error;
  final qq = QqMusic.instance;
  @override
  void initState() {
    super.initState();
    qq.restore().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object _) {
      if (mounted) setState(() => error = 'QQ音乐登录状态读取失败，请重新登录');
    });
  }

  Future<void> login({bool fresh = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (await qq.login(fresh: fresh)) {
        try {
          await qq.userPlaylists();
        } catch (_) {
          error = 'QQ音乐已登录，歌单暂未加载，稍后可重新同步';
        }
        await UnifiedLibrary.instance.sync();
      }
    } catch (e) {
      error = e is MusicServiceError ? e.message : 'QQ音乐登录未完成，请在官方页面完成认证后重试';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseProfileSource() async {
    final home = Home.to;
    final sources = [
      if (home.loginStatus.value == LoginStatus.login) MusicSource.netease,
      if (qq.loggedIn) MusicSource.qq,
    ];
    final source = await showModalBottomSheet<MusicSource>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => AdaptiveOptionSheet(title: '主页头像来源', children: [
          for (final item in sources)
            RadioListTile<MusicSource>(
                key: ValueKey('profile-source:${item.name}'),
                title: Text(item.label),
                secondary: SimpleExtendedImage.avatar(
                    item == MusicSource.qq ? qq.avatarUrl
                        : home.userData.value.profile?.avatarUrl ?? '',
                    width: 36, height: 36),
                value: item,
                toggleable: true,
                groupValue: home.displayProfileSource,
                onChanged: (_) => Navigator.pop(sheet, item)),
        ]));
    if (source == null || !mounted) return;
    try {
      await home.setDisplayProfileSource(source);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('头像来源保存失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('音乐账号与收藏')),
      body: AnimatedBuilder(
          animation: qq,
          builder: (context, _) => SafeArea(
              top: false,
              child: BuYuSettingsList(children: [
                ListTile(
                    title: const Text('网易云音乐'),
                    subtitle: Text(
                        Home.to.loginStatus.value == LoginStatus.login
                            ? Home.to.userData.value.profile?.nickname ?? '已登录'
                            : '未登录'),
                    trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const LoginViewPage()));
                                await UnifiedLibrary.instance.sync();
                                if (mounted) setState(() {});
                              },
                        child: const Text('登录 / 切换'))),
                if (Home.to.loginStatus.value == LoginStatus.login)
                  ListTile(
                      title: const Text('退出网易云登录'),
                      leading: const Icon(TablerIcons.logout),
                      onTap: busy
                          ? null
                          : () async {
                              await libraryAction(
                                  context, () => UserController.signOutNetease(),
                                  success: '已退出网易云登录');
                              if (mounted) setState(() {});
                            }),
                ListTile(
                    title: const Text('QQ音乐'),
                    subtitle: Text(qq.loggedIn
                        ? (qq.nickname.isEmpty ? '已登录QQ音乐' : qq.nickname)
                        : '未登录'),
                    trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => const LoginViewPage(
                                            initialSource: MusicSource.qq)));
                                if (mounted) setState(() {});
                              },
                        child: Text(busy ? '正在登录…' : '登录 / 切换'))),
                if (qq.loggedIn)
                  ListTile(
                      title: const Text('退出QQ音乐登录'),
                      leading: const Icon(TablerIcons.logout),
                      onTap: busy
                          ? null
                          : () async {
                              await libraryAction(context, () => qq.logout(),
                                  success: '已退出QQ音乐登录');
                              if (mounted) setState(() {});
                            }),
                if (Home.to.hasMusicAccount)
                  ListTile(
                      key: const ValueKey('profile-source-setting'),
                      leading: SimpleExtendedImage.avatar(
                          Home.to.displayAvatarUrl, width: 40, height: 40),
                      title: const Text('主页头像来源'),
                      subtitle: Text(Home.to.displayProfileSource?.label ?? ''),
                      trailing: const Icon(TablerIcons.chevron_right),
                      onTap: busy ? null : chooseProfileSource),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.all(16), child: Text(error!)),
                if (error != null)
                  TextButton(
                      onPressed: busy ? null : () => login(fresh: true),
                      child: const Text('重新打开官方登录')),
                ListTile(
                    leading: const Icon(TablerIcons.heart),
                    title: const Text('聚合收藏'),
                    subtitle: const Text('网易云与QQ音乐组合收藏'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const MixedLibraryView()))),
                ListTile(
                    leading: const Icon(TablerIcons.cloud_download),
                    title: const Text('读取两平台BuYu收藏'),
                    subtitle: const Text('合并网易云与QQ音乐云端收藏，保留本地分类'),
                    onTap: () => libraryAction(context,
                        () => UnifiedLibrary.instance.refreshFromCloud(),
                        success: '读取完成，结果可在聚合收藏查看')),
                ListTile(
                    leading: const Icon(TablerIcons.refresh),
                    title: const Text('同步收藏到两个平台'),
                    subtitle: const Text('各平台的歌曲分别保存到自己的“BuYu收藏”歌单'),
                    onTap: () async {
                      await qq.restore();
                      await UnifiedLibrary.instance.sync();
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('同步结果可在聚合收藏查看')));
                    }),
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        '两个平台分别登录、使用各自会员权限。聚合收藏无需登录即可保存，登录后再同步。账号切换时不会将旧账号的待同步歌曲写入新账号。\n\nQQ音乐连接仍为试用，播放和云端歌单同步需以实际账号验证结果为准。')),
              ]))));
}
