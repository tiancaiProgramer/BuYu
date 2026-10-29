import '../music/music_accounts_view.dart';
import '../downloads/downloads_view.dart';
import 'package:auto_route/auto_route.dart';
import 'package:bujuan/common/appearance_store.dart';
import 'package:bujuan/common/audio_quality.dart';
import '../../common/audio_stream_info.dart';
import '../../common/downloads.dart';
import '../../widget/adaptive_option_sheet.dart';
import '../../widget/adaptive_wallpaper.dart';
import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/display_mode.dart';
import 'app_update_tile.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/widget/app_bar.dart';
import 'package:bujuan/widget/landscape_cards.dart';
import 'package:bujuan/widget/simple_extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get/get_state_manager/get_state_manager.dart';
import 'package:image_picker/image_picker.dart';
import '../../routes/router.dart';
import 'image_blur.dart';

class SettingView extends StatefulWidget {
  const SettingView({super.key});
  @override
  State<SettingView> createState() => _SettingViewState();
}

class SettingViewL extends StatefulWidget {
  const SettingViewL({super.key});
  @override
  State<SettingViewL> createState() => _SettingViewStateL();
}

enum _PictureAction {
  portrait,
  landscape,
  clearPortrait,
  clearLandscape,
  reset
}

abstract class _SettingsState<T extends StatefulWidget> extends State<T> {
  bool switchingQuality = false;
  final picker = ImagePicker();
  AppearanceStore get artwork => AppearanceStore(Home.to.box);

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _quality() async {
    if (switchingQuality) return;
    final selected = AudioQuality.parse(Home.to.box.get(audioQualitySp));
    final quality = await showModalBottomSheet<AudioQuality>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => AdaptiveOptionSheet(
            title: '播放音质',
            children: [
              for (final option in AudioQuality.values)
                RadioListTile<AudioQuality>(
                    key: ValueKey('audio-quality:${option.name}'),
                    title: Text(option.label),
                    value: option,
                    groupValue: selected,
                    onChanged: (value) => Navigator.pop(sheet, value)),
            ],
            footer:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ValueListenableBuilder<AudioQualityReport?>(
                  valueListenable: Home.to.audioServeHandler.qualityReport,
                  builder: (_, report, __) => SelectableText(
                      report?.description ?? '播放歌曲后，可在这里查看实际返回音质和文件头核验结果。',
                      key: const ValueKey('audio-quality-report'),
                      style: const TextStyle(fontSize: 14, height: 1.5))),
              const SizedBox(height: 8),
              const Text('优先使用所选音质，不可用时自动降级。核验结果针对当前实际播放文件。',
                  style: TextStyle(fontSize: 12)),
            ])));
    if (quality == null || quality == selected || !mounted) return;
    setState(() => switchingQuality = true);
    try {
      await Home.to.audioServeHandler.setAudioQuality(quality);
      message('已应用音质优先级：${quality.label}');
    } catch (_) {
      message('音质设置未完成，请重试');
    } finally {
      if (mounted) setState(() => switchingQuality = false);
    }
  }

  Future<void> _downloadQuality() async {
    final downloads = Downloads.instance;
    final quality = await showModalBottomSheet<AudioQuality>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => AdaptiveOptionSheet(title: '默认下载音质', children: [
              for (final quality in AudioQuality.values)
                RadioListTile<AudioQuality>(
                    title: Text(quality.label),
                    value: quality,
                    groupValue: downloads.defaultQuality,
                    onChanged: (value) => Navigator.pop(sheet, value)),
            ]));
    if (quality == null) return;
    await Home.to.box.put(Downloads.qualityKey, quality.name);
    downloads.settingsChanged();
    if (mounted) setState(() {});
  }

  Future<void> _downloadFolder() async {
    final action = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => AdaptiveOptionSheet(title: '下载保存位置', children: [
              ListTile(
                  title: const Text('选择文件夹'),
                  subtitle: Text(Downloads.instance.folderLabel),
                  onTap: () => Navigator.pop(sheet, 1)),
              ListTile(
                  title: const Text('恢复默认 Music/BuJuan'),
                  onTap: () => Navigator.pop(sheet, 0)),
            ]));
    if (action == null) return;
    try {
      if (action == 0) {
        await Home.to.box.deleteAll([Downloads.folderKey, Downloads.folderNameKey]);
      } else {
        final folder = await Downloads.channel
            .invokeMapMethod<String, dynamic>('chooseDirectory');
        if (folder == null) return;
        await Home.to.box.putAll({Downloads.folderKey: folder['uri'], Downloads.folderNameKey: folder['name']});
      }
      Downloads.instance.settingsChanged();
      if (mounted) setState(() {});
    } catch (_) {
      message('文件夹未修改，请重新选择并允许保存');
    }
  }

  String _pictureSummary(ArtworkKind kind) {
    final base = artwork.path(kind).isNotEmpty;
    final wide = artwork.path(kind, wide: true).isNotEmpty;
    if (base && wide) return '横竖屏已分别设置';
    if (base) return '已设置通用图，横屏自动适配';
    if (wide) return '仅横屏已设置';
    return '横屏自动适配，也可分别设置';
  }

  Future<void> _pictures(ArtworkKind kind) async {
    final title = kind == ArtworkKind.wallpaper ? '自定义背景' : '自定义启动图';
    final action = await showModalBottomSheet<_PictureAction>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => AdaptiveOptionSheet(title: title, children: [
              ListTile(
                  key: const ValueKey('artwork-portrait'),
                  title: const Text('设置竖屏 / 通用图片'),
                  subtitle: const Text('横屏未单独设置时，自动完整适配此图'),
                  onTap: () => Navigator.pop(sheet, _PictureAction.portrait)),
              ListTile(
                  key: const ValueKey('artwork-landscape'),
                  title: const Text('单独设置横屏图片'),
                  onTap: () => Navigator.pop(sheet, _PictureAction.landscape)),
              ListTile(
                  title: const Text('清除竖屏 / 通用图片'),
                  enabled: artwork.path(kind).isNotEmpty,
                  onTap: () =>
                      Navigator.pop(sheet, _PictureAction.clearPortrait)),
              ListTile(
                  title: const Text('清除横屏图片，恢复自动适配'),
                  enabled: artwork.path(kind, wide: true).isNotEmpty,
                  onTap: () =>
                      Navigator.pop(sheet, _PictureAction.clearLandscape)),
              ListTile(
                  key: const ValueKey('artwork-reset'),
                  title: const Text('全部恢复默认'),
                  onTap: () => Navigator.pop(sheet, _PictureAction.reset)),
            ]));
    if (action == null || !mounted) return;
    try {
      if (action == _PictureAction.clearPortrait ||
          action == _PictureAction.clearLandscape ||
          action == _PictureAction.reset) {
        await artwork.clear(kind,
            wide: action == _PictureAction.reset
                ? null
                : action == _PictureAction.clearLandscape);
        Home.to.refreshBackground();
        if (mounted) setState(() {});
        message('已恢复');
        return;
      }
      final wide = action == _PictureAction.landscape;
      final image = await picker.pickImage(
          source: ImageSource.gallery, requestFullMetadata: false);
      if (image == null || !mounted) return;
      if (kind == ArtworkKind.wallpaper) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ImageBlur(path: image.path, landscape: wide)));
      } else {
        await artwork.importImage(kind, image.path, wide: wide);
        message('启动图已保存');
      }
      if (mounted) setState(() {});
    } catch (_) {
      message('图片保存失败，请重新选择');
    }
  }

  Widget _section(String title, List<Widget> items) => Container(
      margin: EdgeInsets.symmetric(vertical: 10.w),
      decoration: BoxDecoration(
          color: phoneLandscape(context)
              ? Colors.transparent
              : Theme.of(context).colorScheme.onSecondary.withOpacity(.5),
          borderRadius: BorderRadius.circular(25.w)),
      padding: EdgeInsets.symmetric(horizontal: 15.w),
      child: AdaptiveSettingsSection(children: [
        Container(
            padding: EdgeInsets.symmetric(vertical: 15.w, horizontal: 10.w),
            alignment: Alignment.centerLeft,
            child: Text(title,
                style: TextStyle(
                    fontSize: 28.sp,
                    color: Theme.of(context).cardColor.withOpacity(.4)))),
        ...items,
      ]));

  Widget settingsBody() => SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(children: [
        _section('UI设置', [
          if (!DisplayMode.isTv) const _LandscapeSetting(),
          ListTile(
              title: Text('渐变播放背景', style: TextStyle(fontSize: 30.sp)),
              trailing: Obx(() => Icon(
                  Home.to.gradientBackground.value
                      ? TablerIcons.toggle_right
                      : TablerIcons.toggle_left,
                  size: 56.w,
                  color: Theme.of(context).cardColor.withOpacity(
                      Home.to.gradientBackground.value ? .7 : .4))),
              onTap: () {
                Home.to.gradientBackground.value =
                    !Home.to.gradientBackground.value;
                Home.to.box.put(
                    gradientBackgroundSp, Home.to.gradientBackground.value);
              }),
          for (final kind in ArtworkKind.values)
            ListTile(
                key: ValueKey(kind == ArtworkKind.wallpaper
                    ? 'background-setting'
                    : 'splash-setting'),
                title: Text(kind == ArtworkKind.wallpaper ? '自定义背景' : '自定义启动图',
                    style: TextStyle(fontSize: 30.sp)),
                subtitle: Text(_pictureSummary(kind)),
                trailing: Icon(TablerIcons.chevron_right, size: 42.w),
                onTap: () => _pictures(kind)),
          const _HideUnloggedSetting(),
        ]),
        _section('App设置', [
          ListTile(title: Text('音乐账号与收藏', style: TextStyle(fontSize: 30.sp)),
              subtitle: const Text('网易云 / QQ音乐 · 聚合收藏'),
              trailing: Icon(TablerIcons.chevron_right, size: 42.w),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MusicAccountsView()))),
          ListTile(key:const ValueKey('download-manager-setting'),title:Text('下载管理',style:TextStyle(fontSize:30.sp)),subtitle:const Text('下载记录、进度与实际音频信息'),trailing:Icon(TablerIcons.chevron_right,size:42.w),onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const DownloadsView()))),
          ListTile(
              key: const ValueKey('download-quality-setting'),
              title: Text('下载音质', style: TextStyle(fontSize: 30.sp)),
              subtitle: Text(Downloads.instance.defaultQuality.label),
              trailing: Icon(TablerIcons.chevron_right, size: 42.w),
              onTap: _downloadQuality),
          ListTile(
              key: const ValueKey('download-folder-setting'),
              title: Text('下载保存位置', style: TextStyle(fontSize: 30.sp)),
              subtitle: Text(Downloads.instance.folderLabel,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Icon(TablerIcons.chevron_right, size: 42.w),
              onTap: _downloadFolder),
          ListTile(
              key: const ValueKey('audio-quality-setting'),
              title: Text('播放音质', style: TextStyle(fontSize: 30.sp)),
              subtitle: Text(
                  '${AudioQuality.parse(Home.to.box.get(audioQualitySp)).label}（优先）'),
              trailing: switchingQuality
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(TablerIcons.chevron_right, size: 42.w),
              onTap: switchingQuality ? null : _quality),
          AppUpdateTile(
              key: const ValueKey('github-update-setting'),
              titleStyle: TextStyle(fontSize: 30.sp)),
        ]),
      ]));
}

class _SettingViewState extends _SettingsState<SettingView> {
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: MyAppBar(title: const Text('设置')), body: settingsBody());
}

class _SettingViewStateL extends _SettingsState<SettingViewL> {
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
    ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
    Obx(() => AdaptiveWallpaper(
        portrait: Home.to.background.value,
        landscape: Home.to.backgroundLandscape.value,
        portraitBlur: Home.to.backgroundBlur.value,
        landscapeBlur: Home.to.backgroundLandscapeBlur.value)),
    Scaffold(
      backgroundColor: Colors.transparent,
      appBar: Home.to.landscape
          ? null
          : MyAppBar(
              backgroundColor: Colors.transparent,
              centerTitle: false,
              leadingWidth: phoneLandscape(context) ? 68 : null,
              leading: IconButton(
                  key: const ValueKey('settings-account-avatar'),
                  onPressed: () {
                    if (Home.to.hasMusicAccount) {
                      Home.to.myDrawerController.open!();
                    } else {
                      context.router.pushNamed(Routes.login);
                    }
                  },
                  icon: Obx(() => SimpleExtendedImage.avatar(
                      Home.to.displayAvatarUrl,
                      width: 80.w))),
              title: RichText(
                  text: TextSpan(
                      style: TextStyle(
                          fontSize: 36.sp,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold),
                      text: 'Here  ',
                      children: [
                    TextSpan(
                        text: '设置～',
                        style: TextStyle(
                            color:
                                Theme.of(context).primaryColor.withOpacity(.9)))
                  ]))),
      body: settingsBody()),
  ]);
}

class _LandscapeSetting extends StatelessWidget {
  const _LandscapeSetting();
  @override
  Widget build(BuildContext context) => ListTile(
      key: const ValueKey('landscape-setting'),
      title: Text('适配横屏', style: TextStyle(fontSize: 30.sp)),
      trailing: Obx(() => Icon(
          Home.to.landscapeAdaptation.value
              ? TablerIcons.toggle_right
              : TablerIcons.toggle_left,
          size: 56.w,
          color: Theme.of(context)
              .cardColor
              .withOpacity(Home.to.landscapeAdaptation.value ? .7 : .4))),
      onTap: () =>
          Home.to.setLandscapeAdaptation(!Home.to.landscapeAdaptation.value));
}

class _HideUnloggedSetting extends StatelessWidget {
  const _HideUnloggedSetting();
  @override
  Widget build(BuildContext context) => ListTile(
      key: const ValueKey('hide-unlogged-setting'),
      title: Text('未登录隐藏', style: TextStyle(fontSize: 30.sp)),
      subtitle: const Text('隐藏未登录平台的浏览入口、来源选项和云端歌单，云盘与本地收藏始终显示'),
      trailing: Obx(() => Icon(
          Home.to.hideUnlogged.value ? TablerIcons.toggle_right : TablerIcons.toggle_left,
          size: 56.w, color: Theme.of(context).cardColor.withOpacity(
              Home.to.hideUnlogged.value ? .7 : .4))),
      onTap: () async {
        try {
          await Home.to.setHideUnlogged(!Home.to.hideUnlogged.value);
        } catch (_) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('设置保存失败，请重试')));
        }
      });
}
