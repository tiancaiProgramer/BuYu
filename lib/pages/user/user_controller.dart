import 'dart:convert';
import '../../common/music/netease_library.dart';
import '../music/playlist_source_filter.dart';

import 'package:bujuan/common/constants/key.dart';
import 'package:bujuan/common/constants/other.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/user/user_view.dart';
import 'package:bujuan/routes/router.dart';
import 'package:bujuan/widget/enable_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../common/netease_api/src/api/login/bean.dart';
import '../../common/netease_api/src/api/login/api.dart';
import '../../common/netease_api/src/api/play/bean.dart';
import '../../common/netease_api/src/dio_ext.dart';
import '../../common/netease_api/src/netease_api.dart';

enum LoginStatus { login, noLogin }

class UserController extends GetxController {
  UserController({ApiLogin? accountApi}) : _accountApi = accountApi;
  final ApiLogin? _accountApi;
  final playlistSource = PlaylistSource.all.obs;
  final cloudPlaylistsExpanded = true.obs;
  void toggleCloudPlaylists() {
    cloudPlaylistsExpanded.toggle();
    Home.to.box.put('CLOUD_PLAYLISTS_EXPANDED', cloudPlaylistsExpanded.value);
  }

  void setPlaylistSource(PlaylistSource value) {
    playlistSource.value = value;
    Home.to.box.put('PLAYLIST_SOURCE_FILTER', value.name);
  }

  List<Play> playlist = <Play>[].obs;
  Rx<Play> play = Play().obs;
  Rx<PaletteGenerator> palette = PaletteGenerator.fromColors([]).obs;
  RxBool loading = true.obs;
  late BuildContext context;
  final List<UserItem> userItems = [
    UserItem('每日', TablerIcons.calendar,
        routes: Routes.today, color: const Color.fromRGBO(66, 133, 244, .7)),
    UserItem('FM', TablerIcons.vinyl,
        routes: 'playFm', color: const Color.fromRGBO(52, 168, 83, .7)),
    UserItem('播客', TablerIcons.brand_apple_podcast,
        routes: Routes.myRadio, color: const Color.fromRGBO(251, 188, 5, .7)),
    UserItem('云盘', TablerIcons.cloud_fog,
        routes: Routes.cloud, color: const Color.fromRGBO(234, 67, 53, .7))
  ];

  //进度
  @override
  void onInit() {
    super.onInit();
    if (!Get.isRegistered<Home>()) return;
    cloudPlaylistsExpanded.value =
        Home.to.box.get('CLOUD_PLAYLISTS_EXPANDED', defaultValue: true) == true;
    playlistSource.value = PlaylistSource.values.firstWhere(
        (s) => s.name == Home.to.box.get('PLAYLIST_SOURCE_FILTER'),
        orElse: () => PlaylistSource.all);
  }

  @override
  void onReady() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      getUserState();
      _update();
    });
  }

  _update() {
    Https.dioProxy
        .get(
            'https://gitee.com/yasengsuoai/bujuan_version/raw/master/version.json')
        .then((value) async {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String version = packageInfo.version;
      Map<String, dynamic> versionData = value.data
        ..putIfAbsent('oldVersion', () => version);
      //0开启1关闭
      if ((versionData['enable'] ?? 0) == 1) {
        if (context.mounted) {
          showDialog(
              context: context,
              barrierDismissible: false,
              useRootNavigator: true,
              barrierColor: Colors.black87,
              builder: (context) => const EnableView());
        }
        return;
      }
      if (int.parse((versionData['version'] ?? '0').replaceAll('.', '')) >
          int.parse(version.replaceAll('.', ''))) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          // GetIt.instance<RootRouter>().push(const UpdateView().copyWith(queryParams: versionData));
        });
      }
    });
  }

  static UserController get to => Get.find();

  //获取用户信息
  static int _accountRequest = 0;

  Future<bool> getUserState() =>
      _readAccount(_accountApi ?? NeteaseMusicApi(), user: this);

  static Future<bool> refreshNeteaseAccount({ApiLogin? api}) {
    final user =
        Get.isRegistered<UserController>() ? Get.find<UserController>() : null;
    if (api == null && user != null) return user.getUserState();
    return _readAccount(api ?? NeteaseMusicApi(), user: user);
  }

  static Future<bool> _readAccount(ApiLogin api, {UserController? user}) async {
    final request = ++_accountRequest;
    try {
      NeteaseAccountInfoWrap neteaseAccountInfoWrap =
          await api.loginAccountInfo().timeout(const Duration(seconds: 15));
      if (request != _accountRequest || user?.isClosed == true) return false;
      if (neteaseAccountInfoWrap.code == 200 &&
          neteaseAccountInfoWrap.profile != null) {
        await Home.to.box
            .put(loginData, jsonEncode(neteaseAccountInfoWrap.toJson()));
        if (request != _accountRequest || user?.isClosed == true) return false;
        Home.to.userData.value = neteaseAccountInfoWrap;
        Home.to.loginStatus.value = LoginStatus.login;
        user?.getUserPlayList();
        user?._getUserLikeSongIds();
        return true;
      } else if (neteaseAccountInfoWrap.code == 301 ||
          neteaseAccountInfoWrap.code == 200) {
        if (Home.to.loginStatus.value == LoginStatus.login)
          WidgetUtil.showToast('登录失效,请重新登录');
        Home.to.loginStatus.value = LoginStatus.noLogin;
      } else {
        WidgetUtil.showToast('账号资料暂不可用，请稍后重试');
      }
    } catch (e) {
      if (request != _accountRequest || user?.isClosed == true) return false;
      // A transport failure is not evidence that an existing session expired.
      WidgetUtil.showToast('获取用户资料失败，请检查网络');
    }
    return false;
  }

  /// Signing out must also work after the personal route has been replaced.
  static Future<void> signOutNetease() async {
    ++_accountRequest;
    await NeteaseMusicApi().usc.onLogout();
    await Home.to.box.put(loginData, '');
    Home.to.loginStatus.value = LoginStatus.noLogin;
    Home.to.userData.value = NeteaseAccountInfoWrap();
    Home.to.likeIds.clear();
    if (Get.isRegistered<UserController>()) {
      final user = Get.find<UserController>();
      user.play.value = Play();
      user.playlist.clear();
      user.loading.value = false;
    }
  }

  Future<void> clearUser() => signOutNetease();

  Future<void> getUserPlayList() async {
    final account = Home.to.userData.value.profile?.userId;
    if (account == null || Home.to.loginStatus.value != LoginStatus.login)
      return;
    final received = await NeteaseLibrary(Home.to.box).lists();
    await (() async {
      if (Home.to.userData.value.profile?.userId != account ||
          Home.to.loginStatus.value != LoginStatus.login) return;
      List<Play> list = received;
      if (list.isNotEmpty) {
        play.value = list.first;
        final colors = await OtherUtils.getImageColor(
            '${play.value.coverImgUrl ?? ''}?param=500y500');
        if (Home.to.userData.value.profile?.userId != account ||
            Home.to.loginStatus.value != LoginStatus.login) return;
        palette.value = colors;
        playlist
          ..clear()
          ..addAll(list..removeAt(0));
      }
      loading.value = false;
    })();
  }

  _getUserLikeSongIds() async {
    final account = Home.to.userData.value.profile?.userId;
    final request = _accountRequest;
    LikeSongListWrap likeSongListWrap =
        await NeteaseMusicApi().likeSongList(account ?? '-1');
    if (request != _accountRequest ||
        Home.to.loginStatus.value != LoginStatus.login ||
        Home.to.userData.value.profile?.userId != account) return;
    if (likeSongListWrap.code == 200) {
      Home.to.likeIds
        ..clear()
        ..addAll(likeSongListWrap.ids);
    }
  }

  @override
  void onClose() {
    ++_accountRequest;
    // userScrollController.dispose();
    super.onClose();
  }
}
