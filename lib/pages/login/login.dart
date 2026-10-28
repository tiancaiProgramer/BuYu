import '../../widget/buyu_components.dart';
import 'dart:async';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import '../home/home_controller.dart';
import 'dart:typed_data';
import '../../common/music/qq_music.dart';
import '../../common/music/qq_qr_login.dart';
import '../../common/music/music_source.dart';
import '../../common/music/unified_library.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/svg.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../common/constants/icon.dart';
import '../../common/netease_api/src/api/login/api.dart';
import '../../common/netease_api/src/netease_api.dart';
import '../user/user_controller.dart';
import 'web_login.dart';

class LoginViewPage extends StatefulWidget {
  const LoginViewPage(
      {Key? key,
      this.api,
      this.webLogin,
      this.initialSource = MusicSource.netease,
      this.autoQr = true,
      this.statusReader,
      this.signOut,
      this.qqQrFactory})
      : super(key: key);

  final bool Function(MusicSource)? statusReader;
  final Future<void> Function(MusicSource)? signOut;
  final QqQrLogin Function()? qqQrFactory;
  final MusicSource initialSource;
  final bool autoQr;
  final ApiLogin? api;
  final Future<bool> Function()? webLogin;

  @override
  State<LoginViewPage> createState() => _LoginViewStateP();
}

class _LoginViewStateP extends State<LoginViewPage> {
  late final ApiLogin _api = widget.api ?? NeteaseMusicApi();
  Timer? timer;
  String qrCodeUrl = '';
  String _message = '';
  String _qrStatus = '';
  bool _busy = false;
  bool _showQr = false;
  bool _checking = false;
  int _qrRequest = 0;
  late MusicSource _source = widget.initialSource;
  QqQrLogin? _qqQr;
  Uint8List? _qqImage;
  bool _completedNet = false;
  bool _completedQq = false;
  Worker? _accountWorker;
  bool _signedIn(MusicSource source) =>
      widget.statusReader?.call(source) ??
      (source == MusicSource.qq
          ? QqMusic.instance.loggedIn || _completedQq
          : Get.isRegistered<Home>()
              ? Home.to.loginStatus.value == LoginStatus.login
              : _completedNet);
  MusicSource get _other =>
      _source == MusicSource.qq ? MusicSource.netease : MusicSource.qq;
  void _accountsChanged() {
    if (mounted) setState(() {});
  }

  void _finishLogin() {
    _stopQr();
    setState(() {
      if (_source == MusicSource.qq) {
        _completedQq = true;
      } else {
        _completedNet = true;
      }
      _showQr = false;
      _busy = false;
      _message = '';
    });
    if (GetIt.I.isRegistered<UnifiedLibrary>())
      unawaited(UnifiedLibrary.instance.reconcile());
  }

  void _switchSource(MusicSource source) {
    _stopQr();
    setState(() {
      _source = source;
      _showQr = false;
      qrCodeUrl = '';
      _qqImage = null;
      _message = '';
    });
    if (!_signedIn(source)) _refreshCurrent();
  }

  Future<void> _logoutCurrent() async {
    if (_busy) return;
    _stopQr();
    setState(() => _busy = true);
    try {
      if (widget.signOut != null) {
        await widget.signOut!(_source);
      } else if (_source == MusicSource.qq) {
        await QqMusic.instance.logout();
      } else {
        await UserController.signOutNetease();
      }
      if (!mounted) return;
      setState(() {
        if (_source == MusicSource.qq) {
          _completedQq = false;
        } else {
          _completedNet = false;
        }
        _showQr = false;
        _message = '';
      });
    } catch (_) {
      if (mounted) setState(() => _message = '退出登录未完成，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && !_signedIn(_source) && !_busy) _refreshCurrent();
  }

  void _goHome() {
    _stopQr();
    if (Get.isRegistered<Home>()) Home.to.myDrawerController.close?.call();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void initState() {
    super.initState();
    QqMusic.instance.addListener(_accountsChanged);
    QqMusic.instance.restore().then((_) => _accountsChanged());
    if (Get.isRegistered<Home>())
      _accountWorker = ever(Home.to.loginStatus, (_) => _accountsChanged());
    if (widget.autoQr)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_signedIn(_source)) _refreshCurrent();
      });
  }

  void _stopQr() {
    ++_qrRequest;
    timer?.cancel();
    _qqQr?.close();
    _qqQr = null;
    _checking = false;
  }

  Future<void> _refreshCurrent() async {
    if (_signedIn(_source)) return;
    await (_source == MusicSource.qq ? _getQqQr() : getQrCode());
  }

  Future<void> _getQqQr() async {
    _stopQr();
    final request = _qrRequest;
    final qr = widget.qqQrFactory?.call() ?? QqQrLogin();
    _qqQr = qr;
    setState(() {
      _showQr = true;
      _qqImage = null;
      _qrStatus = '正在获取二维码…';
    });
    try {
      final image = await qr.create();
      if (!mounted || request != _qrRequest) return;
      setState(() {
        _qqImage = image;
        _qrStatus = qr.status;
      });
      timer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (_checking || !mounted || request != _qrRequest) return;
        _checking = true;
        try {
          final header = await qr.check(QqMusic.instance);
          if (!mounted || request != _qrRequest) return;
          if (header != null) {
            timer?.cancel();
            setState(() => _qrStatus = '授权成功，正在校验账号…');
            final success = await QqMusic.instance.acceptSession(header,
                isCurrent: () => mounted && request == _qrRequest);
            if (success && mounted && request == _qrRequest) {
              try {
                await QqMusic.instance.userPlaylists();
              } catch (_) {
                /* Login remains valid when lists are temporarily unavailable. */
              }
              if (mounted && request == _qrRequest) {
                _finishLogin();
              }
            }
          } else {
            setState(() => _qrStatus = qr.status);
          }
        } catch (e) {
          if (!qr.active) timer?.cancel();
          if (mounted && request == _qrRequest)
            setState(() => _qrStatus =
                e is MusicServiceError ? e.message : 'QQ扫码连接失败，请刷新或使用网页登录');
        } finally {
          if (request == _qrRequest) _checking = false;
        }
      });
    } catch (e) {
      if (mounted && request == _qrRequest)
        setState(() => _qrStatus =
            e is MusicServiceError ? e.message : 'QQ二维码获取失败，请刷新或使用网页登录');
    }
  }

  Future<void> _openCurrentWeb() async {
    _stopQr();
    setState(() => _showQr = false);
    if (_source != MusicSource.qq) {
      await _openWebLogin();
      return;
    }
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      if (await QqMusic.instance.login(fresh: true)) {
        try {
          await QqMusic.instance.userPlaylists();
        } catch (_) {}
        if (mounted) _finishLogin();
      }
    } catch (e) {
      if (mounted)
        setState(() =>
            _message = e is MusicServiceError ? e.message : 'QQ网页登录未完成，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWebLogin() async {
    if (_busy || _showQr) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final loggedIn = await (widget.webLogin ?? WebLogin().login)();
      if (!mounted || !loggedIn) return;
      if (await UserController.refreshNeteaseAccount()) {
        if (mounted) _finishLogin();
      } else if (mounted) {
        setState(() => _message = '已取得官方登录状态，获取用户资料失败，请检查网络后重试');
      }
    } on WebLoginException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on MissingPluginException {
      if (mounted) setState(() => _message = '此设备暂不支持应用内网页登录，请使用二维码登录');
    } on PlatformException {
      if (mounted) setState(() => _message = '无法打开官方登录页，请重试');
    } catch (_) {
      if (mounted) setState(() => _message = '登录状态校验失败，请检查网络后重新认证');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> getQrCode() async {
    if (_busy) return;
    final request = ++_qrRequest;
    timer?.cancel();
    _checking = false;
    setState(() {
      _showQr = true;
      qrCodeUrl = '';
      _qrStatus = '正在获取二维码…';
    });
    try {
      final key =
          await _api.loginQrCodeKey().timeout(const Duration(seconds: 15));
      if (!mounted || request != _qrRequest) return;
      if (key.code != 200 || key.unikey.isEmpty) {
        setState(() =>
            _qrStatus = key.realMsg.isNotEmpty ? key.realMsg : '二维码获取失败，请刷新重试');
        return;
      }
      setState(() {
        qrCodeUrl = _api.loginQrCodeUrl(key.unikey);
        _qrStatus = '使用网易云音乐 App 扫码登录';
      });
      timer = Timer.periodic(
          const Duration(seconds: 3), (_) => _checkQr(key.unikey, request));
    } catch (_) {
      if (mounted && request == _qrRequest) {
        setState(() => _qrStatus = '二维码获取失败，请检查网络后刷新');
      }
    }
  }

  Future<void> _checkQr(String key, int request) async {
    if (_checking || !mounted || request != _qrRequest) return;
    _checking = true;
    try {
      final result =
          await _api.loginQrCodeCheck(key).timeout(const Duration(seconds: 10));
      if (!mounted || request != _qrRequest) return;
      switch (result.code) {
        case 800:
          timer?.cancel();
          setState(() => _qrStatus = '二维码已过期，请刷新二维码');
          break;
        case 801:
          setState(() => _qrStatus = '使用网易云音乐 App 扫码登录');
          break;
        case 802:
          setState(() => _qrStatus = '已扫码，请在手机上确认登录');
          break;
        case 803:
          setState(() => _qrStatus = '授权成功，正在获取用户资料…');
          final success = await UserController.refreshNeteaseAccount();
          if (!mounted || request != _qrRequest) return;
          if (success) {
            timer?.cancel();
            ++_qrRequest;
            _finishLogin();
          } else {
            setState(() => _qrStatus = '获取用户资料失败，正在重试…');
          }
          break;
        default:
          setState(() => _qrStatus =
              result.realMsg.isNotEmpty ? result.realMsg : '登录状态异常，请刷新二维码');
      }
    } catch (_) {
      if (mounted && request == _qrRequest) {
        setState(() => _qrStatus = '连接失败，正在重试，也可刷新二维码');
      }
    } finally {
      if (request == _qrRequest) _checking = false;
    }
  }

  void _closeQr() {
    _stopQr();
    setState(() {
      _showQr = false;
      qrCodeUrl = '';
    });
  }

  @override
  void dispose() {
    _stopQr();
    QqMusic.instance.removeListener(_accountsChanged);
    _accountWorker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _loginP();
  }

  Widget _loginLandscape(ButtonStyle style, Color readable) {
    final signedIn = _signedIn(_source);
    final compactStyle = style.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(40)));
    return Scaffold(
        body: SafeArea(child: LayoutBuilder(builder: (context, box) {
      final leftWidth = ((box.maxWidth - 48) * .20).clamp(108.0, 156.0);
      return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            SizedBox(
                width: leftWidth,
                key: const ValueKey('login-landscape-platforms'),
                child: SingleChildScrollView(
                    child: Column(children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                          tooltip: '返回',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).maybePop())),
                  SvgPicture.asset(AppIcons.loginTop,
                      height: 44, fit: BoxFit.contain),
                  const SizedBox(height: 12),
                  for (final source in MusicSource.values)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: BuYuChoiceChip(
                            label: Text(source.label),
                            selected: _source == source,
                            onSelected:
                                _busy ? null : (_) => _switchSource(source))),
                ]))),
            const SizedBox(width: 12),
            Expanded(child: LayoutBuilder(builder: (context, qrBox) {
              final qrSize = math.max(0.0,
                  math.min(224.0, math.min(qrBox.maxWidth, qrBox.maxHeight)));
              return Center(
                  child: SizedBox.square(
                      key: const ValueKey('login-landscape-qr'),
                      dimension: qrSize,
                      child: signedIn
                          ? Icon(TablerIcons.circle_check,
                              size: math.min(80, qrSize), color: readable)
                          : _showQr
                              ? _landscapeQr(qrSize)
                              : Icon(TablerIcons.qrcode,
                                  size: math.min(80, qrSize),
                                  color: readable)));
            })),
            const SizedBox(width: 12),
            Expanded(
                child: SingleChildScrollView(
                    key: const ValueKey('login-landscape-actions'),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${signedIn ? '已登录' : '登录'}${_source.label}',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          if (signedIn) ...[
                            FilledButton.icon(
                                key: const ValueKey('login-home'),
                                style: compactStyle,
                                onPressed: _busy ? null : _goHome,
                                icon: const Icon(Icons.home_outlined),
                                label: const Text('跳转主页')),
                            if (!_signedIn(_other)) ...[
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                  key: const ValueKey('login-other'),
                                  style: compactStyle,
                                  onPressed: _busy
                                      ? null
                                      : () => _switchSource(_other),
                                  icon: const Icon(Icons.person_add_alt),
                                  label: Text('继续登录${_other.label}')),
                            ],
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                                key: const ValueKey('login-logout'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: readable,
                                    side: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    minimumSize: const Size.fromHeight(40)),
                                onPressed: _busy ? null : _logoutCurrent,
                                icon: const Icon(Icons.logout),
                                label: Text('退出${_source.label}登录')),
                          ] else ...[
                            if (_showQr) ...[
                              Text(_qrStatus,
                                  style: TextStyle(color: readable)),
                              Wrap(spacing: 8, children: [
                                TextButton(
                                    style: TextButton.styleFrom(
                                        foregroundColor: readable),
                                    onPressed: _refreshCurrent,
                                    child: const Text('刷新二维码')),
                                TextButton(
                                    style: TextButton.styleFrom(
                                        foregroundColor: readable),
                                    onPressed: _closeQr,
                                    child: const Text('关闭二维码')),
                              ]),
                            ] else
                              FilledButton.icon(
                                  style: compactStyle,
                                  onPressed: _busy ? null : _refreshCurrent,
                                  icon: const Icon(TablerIcons.qrcode),
                                  label: const Text('二维码登录')),
                            if (defaultTargetPlatform ==
                                TargetPlatform.android) ...[
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                  style: compactStyle,
                                  onPressed: _busy ? null : _openCurrentWeb,
                                  icon: const Icon(Icons.language),
                                  label: Text(_busy ? '正在认证…' : '官方网页登录')),
                            ],
                            const SizedBox(height: 8),
                            const Text('其他登录方式请前往官方网页；两个平台分别登录，使用各自账号权限。',
                                style: TextStyle(fontSize: 13)),
                          ],
                          if (_message.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Semantics(
                                    liveRegion: true,
                                    child: Text(_message,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)))),
                        ]))),
          ]));
    })));
  }

  Widget _landscapeQr(double size) {
    if (_source == MusicSource.qq && _qqImage != null) {
      return ColoredBox(
          color: Colors.white,
          child: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.memory(_qqImage!,
                  fit: BoxFit.contain, gaplessPlayback: true)));
    }
    if (_source == MusicSource.netease && qrCodeUrl.isNotEmpty) {
      return QrImageView(
          backgroundColor: Colors.white,
          padding: const EdgeInsets.all(8),
          data: qrCodeUrl,
          version: QrVersions.auto,
          size: size);
    }
    return _qrStatus == '正在获取二维码…'
        ? const Center(child: CircularProgressIndicator())
        : const Center(child: Icon(TablerIcons.qrcode, size: 64));
  }

  Widget _loginP() {
    final colors = Theme.of(context).colorScheme;
    final qrSize = math.max(
        80.0, math.min(224.0, MediaQuery.sizeOf(context).shortestSide - 100));
    final readable = ThemeData.estimateBrightnessForColor(
                Theme.of(context).scaffoldBackgroundColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
    final style = FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        minimumSize: const Size.fromHeight(48));
    if (MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height) {
      return _loginLandscape(style, readable);
    }
    return Scaffold(
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: IconButton(
                                      tooltip: '返回',
                                      icon: const Icon(Icons.close),
                                      onPressed: () =>
                                          Navigator.of(context).maybePop())),
                              SvgPicture.asset(AppIcons.loginTop,
                                  height: math.min(80,
                                      MediaQuery.sizeOf(context).height * .13),
                                  fit: BoxFit.contain),
                              const SizedBox(height: 12),
                              Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  children: [
                                    for (final source in MusicSource.values)
                                      BuYuChoiceChip(
                                          label: Text(source.label),
                                          selected: _source == source,
                                          onSelected: _busy
                                              ? null
                                              : (_) => _switchSource(source))
                                  ]),
                              const SizedBox(height: 12),
                              Text(
                                  '${_signedIn(_source) ? '已登录' : '登录'}${_source.label}',
                                  textAlign: TextAlign.center,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 16),
                              if (_signedIn(_source)) ...[
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                    key: const ValueKey('login-home'),
                                    style: style,
                                    onPressed: _busy ? null : _goHome,
                                    icon: const Icon(Icons.home_outlined),
                                    label: const Text('跳转主页')),
                                if (!_signedIn(_other)) ...[
                                  const SizedBox(height: 12),
                                  FilledButton.icon(
                                      key: const ValueKey('login-other'),
                                      style: style,
                                      onPressed: _busy
                                          ? null
                                          : () => _switchSource(_other),
                                      icon: const Icon(Icons.person_add_alt),
                                      label: Text('继续登录${_other.label}')),
                                ],
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                    key: const ValueKey('login-logout'),
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: readable,
                                        side: BorderSide(color: colors.primary),
                                        minimumSize: const Size.fromHeight(48)),
                                    onPressed: _busy ? null : _logoutCurrent,
                                    icon: const Icon(Icons.logout),
                                    label: Text('退出${_source.label}登录')),
                              ],
                              if (!_signedIn(_source) && _showQr)
                                Column(children: [
                                  if (_source == MusicSource.qq &&
                                      _qqImage != null)
                                    SizedBox.square(
                                        dimension: qrSize,
                                        child: ColoredBox(
                                            color: Colors.white,
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                child: Image.memory(_qqImage!,
                                                    fit: BoxFit.contain,
                                                    gaplessPlayback: true)))),
                                  if (_source == MusicSource.netease &&
                                      qrCodeUrl.isNotEmpty)
                                    QrImageView(
                                        backgroundColor: Colors.white,
                                        padding: const EdgeInsets.all(8),
                                        data: qrCodeUrl,
                                        version: QrVersions.auto,
                                        size: qrSize),
                                  const SizedBox(height: 12),
                                  Text(_qrStatus,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: readable)),
                                  Wrap(
                                      spacing: 12,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        TextButton(
                                            style: TextButton.styleFrom(
                                                foregroundColor: readable),
                                            onPressed: _refreshCurrent,
                                            child: const Text('刷新二维码')),
                                        TextButton(
                                            style: TextButton.styleFrom(
                                                foregroundColor: readable),
                                            onPressed: _closeQr,
                                            child: const Text('关闭二维码'))
                                      ]),
                                ]),
                              if (!_signedIn(_source) && !_showQr)
                                FilledButton.icon(
                                    style: style,
                                    onPressed: _busy ? null : _refreshCurrent,
                                    icon: const Icon(TablerIcons.qrcode),
                                    label: const Text('二维码登录')),
                              const SizedBox(height: 16),
                              if (!_signedIn(_source) &&
                                  defaultTargetPlatform ==
                                      TargetPlatform.android)
                                FilledButton.icon(
                                    style: style,
                                    onPressed: _busy ? null : _openCurrentWeb,
                                    icon: const Icon(Icons.language),
                                    label: Text(_busy ? '正在认证…' : '官方网页登录')),
                              const SizedBox(height: 12),
                              if (!_signedIn(_source))
                                const Text('其他登录方式请前往官方网页；两个平台分别登录，使用各自账号权限。',
                                    textAlign: TextAlign.center),
                              if (_message.isNotEmpty)
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Semantics(
                                        liveRegion: true,
                                        child: Text(_message,
                                            style: TextStyle(
                                                color: colors.error)))),
                            ]))))));
  }
}
