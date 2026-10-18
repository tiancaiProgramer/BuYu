import 'dart:async';
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
  const LoginViewPage({Key? key, this.api, this.webLogin}) : super(key: key);

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

  Future<void> _openWebLogin() async {
    if (_busy || _showQr) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final loggedIn = await (widget.webLogin ?? WebLogin().login)();
      if (!mounted || !loggedIn) return;
      if (await UserController.to.getUserState()) {
        if (mounted) Navigator.of(context).pop(true);
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
          final success = await UserController.to.getUserState();
          if (!mounted || request != _qrRequest) return;
          if (success) {
            timer?.cancel();
            ++_qrRequest;
            Navigator.of(context).pop(true);
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
      _checking = false;
    }
  }

  void _closeQr() {
    ++_qrRequest;
    timer?.cancel();
    setState(() {
      _showQr = false;
      qrCodeUrl = '';
    });
  }

  @override
  void dispose() {
    ++_qrRequest;
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _loginP();
  }

  Widget _loginP() {
    final disabled = _busy;
    final colors = Theme.of(context).colorScheme;
    final loginButtonStyle = FilledButton.styleFrom(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      minimumSize: const Size.fromHeight(52),
    );
    // This app's dark theme uses onSurface as a background color.
    final readable = ThemeData.estimateBrightnessForColor(
                Theme.of(context).scaffoldBackgroundColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Scaffold(
      body: Stack(children: [
        SafeArea(
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
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close),
                          )),
                      SvgPicture.asset(AppIcons.loginTop,
                          height: math.min(
                              100, MediaQuery.sizeOf(context).height * .16),
                          fit: BoxFit.contain),
                      const SizedBox(height: 12),
                      Text('登录网易云音乐',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 20),
                      const Text(
                        '在网易云官方网页完成登录和安全验证，成功后自动返回 BuYu。网页提供的登录方式以网易云当前页面为准。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (defaultTargetPlatform == TargetPlatform.android)
                        FilledButton.icon(
                          style: loginButtonStyle,
                          onPressed: disabled ? null : _openWebLogin,
                          icon: const Icon(Icons.language),
                          label: Text(_busy ? '正在认证…' : '官方网页登录'),
                        ),
                      if (_message.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                              liveRegion: true,
                              child: Text(_message,
                                  style: TextStyle(color: colors.error))),
                        ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: loginButtonStyle,
                        onPressed: disabled ? null : getQrCode,
                        icon: const Icon(TablerIcons.qrcode),
                        label: const Text('二维码登录'),
                      ),
                    ]),
              ),
            ),
          ),
        ),
        if (_showQr)
          Positioned.fill(
              child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor.withOpacity(.97),
            child: SafeArea(
                child: Center(
                    child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (qrCodeUrl.isNotEmpty)
                  QrImageView(
                    backgroundColor: Colors.white,
                    data: qrCodeUrl,
                    version: QrVersions.auto,
                    size: math.max(
                        80,
                        math.min(260,
                            MediaQuery.sizeOf(context).shortestSide - 100)),
                  ),
                const SizedBox(height: 20),
                Text(_qrStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(spacing: 12, children: [
                  TextButton(
                      style: TextButton.styleFrom(foregroundColor: readable),
                      onPressed: getQrCode,
                      child: const Text('刷新二维码')),
                  TextButton(
                      style: TextButton.styleFrom(foregroundColor: readable),
                      onPressed: _closeQr,
                      child: const Text('关闭二维码')),
                ]),
              ]),
            ))),
          )),
      ]),
    );
  }
}
