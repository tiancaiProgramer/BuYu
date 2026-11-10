import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bujuan/common/constants/platform_utils.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'api/dj/api.dart';
import 'api/event/api.dart';
import 'api/login/api.dart';
import 'api/login/bean.dart';
import 'api/play/api.dart';
import 'api/search/api.dart';
import 'api/uncategorized/api.dart';
import 'api/user/api.dart';
import 'dio_ext.dart';
import 'netease_bean.dart';
import 'netease_handler.dart';
import 'session_recovery.dart';

class NeteaseMusicApi
    with
        ApiPlay,
        ApiDj,
        ApiLogin,
        ApiUser,
        ApiEvent,
        ApiSearch,
        ApiUncategorized {
  static NeteaseMusicApi? _neteaseMusicApi;

  static late CookieManager cookieManager;
  static late PathProvider pathProvider;
  static final _installed = Expando<List<Interceptor>>();
  static Dio Function()? _refreshClientFactory;

  static Future<bool> init(
      {PathProvider? provider,
      bool debug = false,
      Dio Function()? refreshClientFactory}) async {
    provider ??= PathProvider();
    pathProvider = provider;

    await provider.init();

    _refreshClientFactory = refreshClientFactory;
    cookieManager = NeteaseSessionCookies(
        PersistCookieJar(storage: FileStorage(provider.getCookieSavedPath())),
        revision: () => NeteaseMusicApi().usc.sessionRevision,
        authenticated: () => NeteaseMusicApi().usc.isLogined);

    _initDio(Https.dio, debug, true);
    await NeteaseMusicApi().usc.init();

    return true;
  }

  static Dio _initDio(Dio dio, bool debug, bool refreshToken) {
    for (final interceptor in _installed[dio] ?? <Interceptor>[]) {
      dio.interceptors.remove(interceptor);
    }
    final installed = <Interceptor>[
      cookieManager,
      InterceptorsWrapper(
          onRequest: neteaseInterceptor,
          onResponse:
              (Response response, ResponseInterceptorHandler handler) async {
            if (response.data is String) {
              try {
                response.data = jsonDecode(response.data);
              } catch (e) {}
            }
            handler.next(response);
          })
    ];
    if (refreshToken) {
      installed.add(NeteaseSessionRecovery(
          dio: dio,
          revision: () => NeteaseMusicApi().usc.sessionRevision,
          authenticated: () => NeteaseMusicApi().usc.isLogined,
          signature: (uri) => loadCookiesHash(host: uri),
          official: (uri) => uri.scheme == 'https' && HOSTS.contains(uri.host),
          invalidate: (revision) =>
              NeteaseMusicApi().usc.onLogout(expectedRevision: revision),
          refresh: () async {
            final client = _refreshClientFactory?.call() ??
                Dio(BaseOptions(
                    connectTimeout: const Duration(seconds: 8),
                    sendTimeout: const Duration(seconds: 8),
                    receiveTimeout: const Duration(seconds: 10)));
            final cancel = CancelToken();
            try {
              final response = await NeteaseMusicApi()
                  .loginRefresh(
                      dio: _initDio(client, false, false), cancelToken: cancel)
                  .timeout(const Duration(seconds: 15), onTimeout: () {
                cancel.cancel('网易云登录刷新超时');
                throw TimeoutException('网易云登录刷新超时');
              });
              return response.code;
            } finally {
              client.close(force: true);
            }
          }));
    }

    if (debug) {
      installed.add(PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          responseHeader: true,
          error: true,
          compact: true,
          maxWidth: 90,
          logPrint: (object) {
            if (object is String) {
              print(object.replaceAll('║', ''));
            }
          }));
    }
    _installed[dio] = installed;
    dio.interceptors.addAll(installed);
    return dio;
  }

  UserLoginStateController usc = UserLoginStateController();

  NeteaseMusicApi._internal() {
    usc.init();
  }

  factory NeteaseMusicApi() {
    return _neteaseMusicApi ??= NeteaseMusicApi._internal();
  }
}

class UserLoginStateController {
  int _sessionRevision = 0;
  int get sessionRevision => _sessionRevision;
  LoginState? _curLoginState;

  StreamController? _controller;

  UserLoginStateController();

  late final Future<void> _initialization = _initialize();

  Future<void> init() => _initialization;

  Future<void> _initialize() async {
    _checkCreateSavePath();
    await _readAccountInfo();
    _refreshLoginState((await loadCookies()).isNotEmpty && _accountInfo != null
        ? LoginState.Logined
        : LoginState.Logout);
  }

  NeteaseAccountInfoWrap? _accountInfo;

  NeteaseAccountInfoWrap? get accountInfo {
    return _accountInfo;
  }

  AnonimousLoginRet? _anonimousLoginRet;

  AnonimousLoginRet? get anonimousLoginInfo {
    if (accountInfo != null) {
      _anonimousLoginRet = null;
    }
    return _anonimousLoginRet;
  }

  bool get isLogined {
    return _curLoginState == LoginState.Logined;
  }

  StreamSubscription listenLoginState(
      void Function(LoginState event, NeteaseAccountInfoWrap? accountInfoWrap)
          onChange) {
    var controller = _controller;
    if (controller == null) {
      _controller = controller = StreamController.broadcast(sync: true);
    }
    return controller.stream.listen((t) {
      onChange(t, accountInfo);
    });
  }

  Future<void> onLogined(NeteaseAccountInfoWrap infoWrap,
      {int? expectedRevision}) async {
    await init();
    if (expectedRevision != null && expectedRevision != _sessionRevision)
      return;
    // Failed credentials and anonymous account responses are not a login.
    if (infoWrap.code != RET_CODE_OK ||
        infoWrap.profile == null ||
        infoWrap.profile!.userId.isEmpty) return;
    final revision = _sessionRevision;
    await NeteaseSessionWrites.run(() async {
      if (revision != _sessionRevision) return;
      await _saveAccountInfo(infoWrap);
      if (revision != _sessionRevision) return;
      if (!isLogined ||
          _accountInfo?.profile?.userId != infoWrap.profile!.userId) {
        ++_sessionRevision;
      }
      _accountInfo = infoWrap;
      _refreshLoginState(LoginState.Logined);
    });
  }

  void onAnonimousLogined(AnonimousLoginRet anonimousLoginRet) {
    _anonimousLoginRet = anonimousLoginRet;
  }

  Future<void> onLogout({int? expectedRevision}) async {
    if (expectedRevision != null && expectedRevision != _sessionRevision)
      return;
    ++_sessionRevision;
    _accountInfo = null;
    _refreshLoginState(LoginState.Logout);
    await NeteaseSessionWrites.run(() async {
      await deleteAllCookie();
      await _saveAccountInfo(null);
    });
  }

  Future<void> _saveAccountInfo(NeteaseAccountInfoWrap? infoWrap) async {
    await _saveFile().writeAsString(jsonEncode(infoWrap), flush: true);
  }

  Future<void> _readAccountInfo() async {
    try {
      var accountInfo = _saveFile().readAsStringSync();

      _accountInfo = NeteaseAccountInfoWrap.fromJson(jsonDecode(accountInfo));
      if (_accountInfo!.code != RET_CODE_OK ||
          _accountInfo!.profile == null ||
          _accountInfo!.profile!.userId.isEmpty) {
        throw const FormatException('Invalid cached account');
      }
    } catch (e) {
      print('login info error');
      await onLogout();
    }
  }

  File _saveFile() => File(
      NeteaseMusicApi.pathProvider.getDataSavedPath() + "_accountInfo.json");

  _checkCreateSavePath() {
    var file = _saveFile();
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
  }

  void _refreshLoginState(LoginState state) {
    var controller = _controller;
    if (controller != null && _curLoginState != state) {
      controller.add(state);
    }
    _curLoginState = state;
  }

  void destroy() {
    _controller?.close();
  }
}

enum LoginState {
  Logined,
  Logout,
}

class PathProvider {
  var _cookiePath = '';
  var _dataPath = '';

  init() async {
    if (PlatformUtils.isWeb) return;
    _cookiePath =
        "${(await getApplicationSupportDirectory()).absolute.path}/zmusic/.cookies/";
    _dataPath =
        "${(await getApplicationSupportDirectory()).absolute.path}/zmusic/.data/";
  }

  String getCookieSavedPath() {
    return _cookiePath;
  }

  String getDataSavedPath() {
    return _dataPath;
  }
}
