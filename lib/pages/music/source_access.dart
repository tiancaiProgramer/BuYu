// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../common/music/music_source.dart';
import '../../common/music/qq_music.dart';
import '../home/home_controller.dart';
import '../user/home_account_visibility.dart';
import '../user/user_controller.dart';

/// Observes the shared hide preference and both accounts on browsing pages.
class SourceAccess extends ChangeNotifier {
  SourceAccess({this.statusReader}) {
    if (home != null) {
      _worker = everAll([home!.hideUnlogged, home!.loginStatus, home!.userData],
          (_) => _changed());
    }
    _signature = _readSignature();
    qq.addListener(_changed);
  }
  final bool Function(MusicSource)? statusReader;
  final Home? home = Get.isRegistered<Home>() ? Home.to : null;
  final QqMusic qq = QqMusic.instance;
  Worker? _worker;
  late String _signature;
  bool signedIn(MusicSource source) =>
      statusReader?.call(source) ??
      (source == MusicSource.qq
          ? qq.loggedIn
          : home?.loginStatus.value == LoginStatus.login);
  String account(MusicSource source) {
    if (!signedIn(source)) return '';
    return source == MusicSource.qq
        ? qq.account
        : '${home?.userData.value.profile?.userId ?? ''}';
  }

  HomeAccountVisibility get visibility => HomeAccountVisibility(
      hideUnlogged: home?.hideUnlogged.value ?? false,
      neteaseLoggedIn: signedIn(MusicSource.netease),
      qqLoggedIn: signedIn(MusicSource.qq));
  List<MusicSource> get sources => visibility.musicSources;
  String _readSignature() =>
      '${visibility.hideUnlogged}:${signedIn(MusicSource.netease)}:${signedIn(MusicSource.qq)}:${account(MusicSource.netease)}:${account(MusicSource.qq)}';
  void _changed() {
    final next = _readSignature();
    if (next == _signature) return;
    _signature = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _worker?.dispose();
    qq.removeListener(_changed);
    super.dispose();
  }
}
