// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../common/netease_api/src/api/login/bean.dart';
import '../../common/netease_api/src/netease_api.dart';
import '../../common/netease_api/src/netease_handler.dart';

class WebLoginException implements Exception {
  const WebLoginException(this.message);
  final String message;
}

/// Only the native, non-exported official-page activity supplies this session.
class WebLogin {
  WebLogin({this.channel = const MethodChannel('bujuan/auth'), Dio? verifier})
      : _verifier = verifier;
  final MethodChannel channel;
  final Dio? _verifier;

  Future<bool> login() async {
    final header = await channel.invokeMethod<String>('webLogin');
    if (header == null) return false;
    final cookies = _parseCookies(header);
    final dio = _verifier ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 15),
        ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: neteaseInterceptor));
    try {
      final request = NeteaseMusicApi().loginAccountInfoDioMetaData();
      request.options!.extra!['sessionCookies'] = cookies;
      final response = await dio.postUri(request.uri,
          data: request.data, options: request.options);
      final body = response.data;
      if (body is! Map) throw const WebLoginException('官方登录状态校验失败，请重新认证');
      final account =
          NeteaseAccountInfoWrap.fromJson(Map<String, dynamic>.from(body));
      if (account.code != 200 ||
          account.profile == null ||
          account.profile!.userId.isEmpty ||
          account.profile!.userId == '0') {
        throw const WebLoginException('尚未完成官方登录，请返回网页完成验证后重试');
      }
      // No persistent cookie or account state changes before successful validation.
      final jar = NeteaseMusicApi.cookieManager.cookieJar;
      final host = Uri.parse(HOST);
      final previous = await jar.loadForRequest(host);
      try {
        // Remove host-only duplicates and stale CSRF cookies from the old session.
        await jar.delete(host, true);
        await jar.saveFromResponse(host, cookies);
        await NeteaseMusicApi().usc.onLogined(account);
      } catch (_) {
        await jar.delete(host, true);
        await jar.saveFromResponse(host, previous);
        rethrow;
      }
      return true;
    } finally {
      dio.close(force: true);
    }
  }

  List<Cookie> _parseCookies(String header) {
    if (header.length > 65536 || RegExp(r'[\r\n\x00]').hasMatch(header)) {
      throw const WebLoginException('官方登录状态不完整，请重新认证');
    }
    final cookies = <Cookie>[];
    for (final item in header.split(';')) {
      final index = item.indexOf('=');
      if (index <= 0) continue;
      final name = item.substring(0, index).trim();
      final value = item.substring(index + 1).trim();
      if (!['MUSIC_U', '__csrf', '__remember_me', 'NMTID'].contains(name) ||
          value.isEmpty) continue;
      cookies.add(Cookie(name, value)
        ..domain = '.music.163.com'
        ..path = '/'
        ..secure = true
        ..httpOnly = true);
    }
    if (!cookies.any((cookie) => cookie.name == 'MUSIC_U')) {
      throw const WebLoginException('尚未取得官方登录状态，请重新认证');
    }
    return cookies;
  }
}
