// Community maintenance and new features: tiancaiProgramer.
import 'dart:typed_data';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'music_source.dart';
import 'qq_music.dart';

class QqQrLogin {
  QqQrLogin({Dio? dio})
      : client = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15)));
  final Dio client;
  final CancelToken token = CancelToken();
  String _signature = '';
  String? _completedHeader;
  bool get active => _signature.isNotEmpty;
  String status = '使用手机QQ扫码登录';
  static int hash(String value, [int seed = 0]) {
    var h = seed;
    for (final c in value.codeUnits) {
      h = ((h << 5) + h + c) & 0x7fffffff;
    }
    return h;
  }

  Options options({bool bytes = false, String? cookie}) => Options(
          followRedirects: false,
          validateStatus: (c) => c != null && c >= 200 && c < 400,
          responseType: bytes ? ResponseType.bytes : ResponseType.plain,
          headers: {
            'Referer': 'https://xui.ptlogin2.qq.com/',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            if (cookie != null) 'Cookie': cookie
          });
  Map<String, String> cookies(Response response, {Uri? forUri}) {
    final origin = response.realUri;
    final target = forUri ?? origin;
    final scoped = <String, Cookie>{};
    for(final header in response.headers['set-cookie'] ?? <String>[]) {
      try {
        final cookie = Cookie.fromSetCookieValue(header);
        final domain = (cookie.domain ?? origin.host).toLowerCase().replaceFirst(RegExp(r'^\.'), '');
        // A response can clear a parent-domain cookie while issuing a valid
        // same-name cookie for graph.qq.com. Keep those scopes independent.
        if(origin.host != domain && !origin.host.endsWith('.$domain')) continue;
        final path = cookie.path ?? '/';
        final key = '${cookie.name}|$domain|$path';
        final valid = cookie.value.isNotEmpty && (cookie.maxAge == null || cookie.maxAge! > 0) &&
          (cookie.expires == null || cookie.expires!.isAfter(DateTime.now().toUtc()));
        if(!valid) { scoped.remove(key); continue; }
        if(target.host != domain && (cookie.domain == null || !target.host.endsWith('.$domain'))) continue;
        if(!target.path.startsWith(path) || cookie.secure && target.scheme != 'https') continue;
        scoped[key] = cookie;
      } on FormatException { /* Ignore malformed response cookies. */ }
    }
    final records = scoped.entries.toList()..sort((a,b) => b.key.split('|')[1].length.compareTo(a.key.split('|')[1].length));
    final result = <String,String>{};
    for(final entry in records) result.putIfAbsent(entry.value.name, () => entry.value.value);
    return result;
  }

  Future<Uint8List> create() async {
    final r =
        await client.get<List<int>>('https://ssl.ptlogin2.qq.com/ptqrshow',
            queryParameters: {
              'appid': '716027609',
              'e': '2',
              'l': 'M',
              's': '3',
              'd': '72',
              'v': '4',
              't': '${Random.secure().nextDouble()}',
              'daid': '383',
              'pt_3rd_aid': '100497308'
            },
            options: options(bytes: true),
            cancelToken: token);
    _signature = cookies(r)['qrsig'] ?? '';
    if (_signature.isEmpty ||
        r.data == null ||
        r.data!.length < 8 ||
        r.data!.take(4).join(',') != '137,80,78,71')
      throw const MusicServiceError('QQ二维码获取失败，请刷新或使用网页登录');
    return Uint8List.fromList(r.data!);
  }

  Future<String?> check(QqMusic qq) async {
    if (_completedHeader != null) return _completedHeader;
    if (_signature.isEmpty) return null;
    final r = await client.get<String>('https://ssl.ptlogin2.qq.com/ptqrlogin',
        queryParameters: {
          'u1': 'https://graph.qq.com/oauth2.0/login_jump',
          'ptqrtoken': hash(_signature),
          'ptredirect': '0',
          'h': '1',
          't': '1',
          'g': '1',
          'from_ui': '1',
          'ptlang': '2052',
          'action': '0-0-${DateTime.now().millisecondsSinceEpoch}',
          'js_ver': '20102616',
          'js_type': '1',
          'pt_uistyle': '40',
          'aid': '716027609',
          'daid': '383',
          'pt_3rd_aid': '100497308',
          'has_onekey': '1'
        },
        options: options(cookie: 'qrsig=$_signature'),
        cancelToken: token);
    final text = r.data ?? '';
    if (!text.trimLeft().startsWith('ptuiCB('))
      throw const MusicServiceError('QQ扫码状态异常，请刷新');
    final args =
        RegExp("'([^']*)'").allMatches(text).map((m) => m.group(1)!).toList();
    if (args.isEmpty) throw const MusicServiceError('QQ扫码状态无法识别');
    switch (args.first) {
      case '66':
        status = '使用手机QQ扫码登录';
        return null;
      case '67':
        status = '已扫码，请在QQ确认登录';
        return null;
      case '65':
        _signature = '';
        throw const MusicServiceError('二维码已过期，请刷新');
      case '0':
        break;
      default:
        throw const MusicServiceError('QQ扫码未完成，请刷新或使用网页登录');
    }
    final redirect = args.length > 2 ? Uri.tryParse(args[2]) : null;
    if (redirect == null ||
        redirect.scheme != 'https' ||
        !{'ssl.ptlogin2.graph.qq.com', 'ptlogin2.qq.com', 'ssl.ptlogin2.qq.com'}
            .contains(redirect.host) ||
        redirect.port != 443 ||
        redirect.path != '/check_sig' ||
        redirect.userInfo.isNotEmpty)
      throw const MusicServiceError('QQ授权跳转地址异常');
    final uin = redirect.queryParameters['uin'] ?? '';
    final signature = redirect.queryParameters['ptsigx'] ?? '';
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(uin) || signature.isEmpty)
      throw const MusicServiceError('QQ扫码未返回完整授权，请刷新重试');
    // The callback supplies identity/signature, not a complete OAuth cookie request.
    // Finish the official check_sig handshake with the music application's fields.
    final signed =
        await client.get('https://ssl.ptlogin2.graph.qq.com/check_sig',
            queryParameters: {
              'uin': uin,
              'pttype': '1',
              'service': 'ptqrlogin',
              'nodirect': '0',
              'ptsigx': signature,
              's_url': 'https://graph.qq.com/oauth2.0/login_jump',
              'ptlang': '2052',
              'ptredirect': '100',
              'aid': '716027609',
              'daid': '383',
              'j_later': '0',
              'low_login_hour': '0',
              'regmaster': '0',
              'pt_login_type': '3',
              'pt_aid': '0',
              'pt_aaid': '16',
              'pt_light': '0',
              'pt_3rd_aid': '100497308'
            },
            options: options(),
            cancelToken: token);
    final oauthUri = Uri.parse('https://graph.qq.com/oauth2.0/authorize');
    final auth = cookies(signed, forUri: oauthUri);
    var response = signed;
    // Some accounts issue the OAuth cookie on the official login-jump response.
    // Check each hop explicitly; never forward a ticket to an arbitrary URL.
    for (var hop = 0; hop < 3 && (auth['p_skey'] ?? '').isEmpty; hop++) {
      final location = response.headers.value('location');
      if(location == null) break;
      final next = response.realUri.resolve(location);
      if(next.scheme != 'https' || next.port != 443 || next.userInfo.isNotEmpty ||
        !{'ssl.ptlogin2.graph.qq.com','graph.qq.com'}.contains(next.host) ||
        !{'/check_sig','/oauth2.0/login_jump'}.contains(next.path)) break;
      response = await client.getUri(next, options: options(cookie:auth.entries.map((e) => '${e.key}=${e.value}').join('; ')), cancelToken:token);
      auth.addAll(cookies(response, forUri: oauthUri));
    }
    if ((auth['p_skey'] ?? '').isEmpty) {
      throw const MusicServiceError('QQ扫码授权尚未完成，请刷新二维码重试');
    }
    final authorized = await client.post(
        'https://graph.qq.com/oauth2.0/authorize',
        data: {
          'response_type': 'code',
          'client_id': '100497308',
          'redirect_uri':
              'https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/',
          'scope': 'get_user_info,get_app_friends',
          'state': 'state',
          'switch': '',
          'from_ptlogin': '1',
          'src': '1',
          'update_auth': '1',
          'openapi': '1010_1030',
          'g_tk': hash(auth['p_skey']!, 5381),
          'auth_time': '${DateTime.now().millisecondsSinceEpoch}',
          'ui': List.generate(
              16,
              (_) => Random.secure()
                  .nextInt(256)
                  .toRadixString(16)
                  .padLeft(2, '0')).join()
        },
        options: options(
                cookie:
                    auth.entries.map((e) => '${e.key}=${e.value}').join('; '))
            .copyWith(contentType: Headers.formUrlEncodedContentType),
        cancelToken: token);
    final location = Uri.tryParse(authorized.headers.value('location') ?? '');
    if (location == null ||
        location.scheme != 'https' ||
        location.host != 'y.qq.com' ||
        location.path != '/portal/wx_redirect.html' ||
        (location.queryParameters['code'] ?? '').isEmpty)
      throw const MusicServiceError('QQ扫码需要进一步验证，请使用官方网页登录');
    if (token.isCancelled) return null;
    _completedHeader =
        await qq.exchangeQrCode(location.queryParameters['code']!);
    return _completedHeader;
  }

  void close() {
    token.cancel();
    _signature = '';
    _completedHeader = null;
    client.close(force: true);
  }
}
