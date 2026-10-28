// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../audio_quality.dart';
import 'music_source.dart';

/// Independent transport: QQ credentials are never sent through the Netease client.
class QqMusic extends ChangeNotifier {
  QqMusic({Dio? dio, this.channel = const MethodChannel('buyu/qqmusic')})
      : client = dio ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 15)));
  static QqMusic get instance {
    if (!GetIt.I.isRegistered<QqMusic>())
      GetIt.I
          .registerSingleton<QqMusic>(QqMusic(), dispose: (q) => q.dispose());
    return GetIt.I<QqMusic>();
  }

  final Dio client;
  final MethodChannel channel;
  Map<String, String> _cookies = {};
  bool _restored = false;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void>? _restoring;
  String nickname = '';
  String avatarUrl = '';
  static const profileCacheKey = 'QQ_PUBLIC_PROFILE';
  int _profileRevision = 0;
  Box? get _profileBox => GetIt.I.isRegistered<Box>() ? GetIt.I<Box>() : null;

  static String profileAvatar(Map profile) {
    for (final field in ['headpic', 'avatar', 'avatarUrl', 'logo', 'AvatarUrl']) {
      var value = '${profile[field] ?? ''}'.trim();
      if (value.startsWith('//')) value = 'https:$value';
      final uri = Uri.tryParse(value);
      if (uri != null && ['http', 'https'].contains(uri.scheme) && uri.host.isNotEmpty) {
        return uri.replace(scheme: 'https').toString();
      }
    }
    return '';
  }

  Future<void> _saveProfile(Map info) async {
    nickname = clean(info['nick'] ?? info['nickname'] ?? 'QQ音乐');
    avatarUrl = profileAvatar(info);
    try {
      await _profileBox?.put(profileCacheKey, {
        'account': account, 'nickname': nickname, 'avatarUrl': avatarUrl
      });
    } catch (_) { /* Public profile caching must not invalidate a login. */ }
  }

  Future<void> refreshProfile() async {
    await restore();
    if (!loggedIn || _disposed) return;
    final bound = account, revision = _profileRevision;
    final info = await _webProfile(Map.of(_cookies));
    if (!loggedIn || _disposed || account != bound || revision != _profileRevision) return;
    await _saveProfile(info);
    if (loggedIn && account == bound && revision == _profileRevision) _notify();
  }
  List<SourcePlaylist> playlists = [];
  String get account => _account(_cookies);
  static String _account(Map<String, String> cookies) {
    final key = cookies['qqmusic_key'] ?? cookies['qm_keyst'] ?? '';
    final raw = cookies['qqmusic_uin'] ??
        (key.startsWith('W_X')
            ? cookies['wxuin'] ?? cookies['uin']
            : cookies['uin'] ?? cookies['wxuin']);
    final value = (raw ?? '').replaceFirst(RegExp(r'^o0*'), '');
    return RegExp(r'^[0-9]+$').hasMatch(value) &&
            value.replaceAll('0', '').isNotEmpty
        ? value
        : '';
  }

  bool get loggedIn => account.isNotEmpty && key.isNotEmpty;
  String get key => _cookies['qqmusic_key'] ?? _cookies['qm_keyst'] ?? '';
  static Map<String, String> parseCookies(String header) {
    if (header.length > 65536 || RegExp(r'[\r\n\x00]').hasMatch(header))
      throw const MusicServiceError('QQ登录状态无效，请重新登录');
    const names = {
      'uin',
      'wxuin',
      'qqmusic_uin',
      'qqmusic_key',
      'qm_keyst',
      'login_type',
      'tmeLoginType'
    };
    final result = <String, String>{};
    for (final part in header.split(';')) {
      final i = part.indexOf('=');
      if (i > 0 &&
          names.contains(part.substring(0, i).trim()) &&
          part.substring(i + 1).trim().isNotEmpty)
        result[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    return result;
  }

  Future<void> restore() async {
    if (_restored) return;
    await (_restoring ??= _restore());
  }

  Future<void> _restore() async {
    try {
      final saved = await channel.invokeMethod<String>('readSession');
      if (saved != null) _cookies = parseCookies(saved);
      final cached = _profileBox?.get(profileCacheKey);
      if (loggedIn && cached is Map && cached['account'] == account) {
        nickname = '${cached['nickname'] ?? ''}';
        avatarUrl = profileAvatar({'avatarUrl': cached['avatarUrl']});
      }
    } on MissingPluginException {
      /* Non-Android previews have no persistent session. */
    } on PlatformException {
      _cookies = {};
    } on MusicServiceError {
      _cookies = {};
    } finally {
      _restored = true;
    }
  }

  Future<bool> login({bool fresh = false}) async {
    await restore();
    // Retry a completed official browser login after validation/network failure.
    // It remains untrusted until the authenticated web endpoint accepts it.
    final cached = !fresh && !loggedIn
        ? await channel.invokeMethod<String>('readWebSession')
        : null;
    final header = cached ?? await channel.invokeMethod<String>('login');
    if (header == null) return false;
    return acceptSession(header);
  }

  Future<bool> acceptSession(String header, {bool Function()? isCurrent}) async {
    final candidate = parseCookies(header);
    final candidateKey = candidate['qqmusic_key'] ?? candidate['qm_keyst'] ?? '';
    if (_account(candidate).isEmpty || candidateKey.isEmpty) throw const MusicServiceError('请在QQ音乐官方页面完成登录');
    final info = await _webProfile(candidate);
    if (isCurrent != null && !isCurrent()) return false;
    await channel.invokeMethod<void>('saveSession', header);
    _cookies = candidate;
    _restored = true;
    ++_profileRevision;
    await _saveProfile(info);
    playlists = [];
    _notify();
    return true;
  }

  Future<String> exchangeQrCode(String code) async {
    final data = await _request({}, 'QQConnectLogin.LoginServer', 'QQLogin', {'code': code});
    final uin = '${data['musicid'] ?? ''}';
    final musicKey = '${data['musickey'] ?? ''}';
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(uin) || musicKey.isEmpty) throw const MusicServiceError('QQ扫码授权未返回音乐会话，请使用官方网页登录');
    return 'qqmusic_uin=$uin; qqmusic_key=$musicKey; tmeLoginType=2';
  }

  Future<Map> _webProfile(Map<String, String> cookies) async {
    final account = _account(cookies);
    final key = cookies['qqmusic_key'] ?? cookies['qm_keyst'] ?? '';
    try {
      // Web sessions must be checked using the official web endpoint, rather
      // than the separate native-app GetLoginUserInfo credential protocol.
      final response = await client.get<dynamic>(
          'https://c6.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg',
          queryParameters: {
            'g_tk': _csrf(key),
            'format': 'json',
            'inCharset': 'utf-8',
            'outCharset': 'utf-8',
            'notice': 0,
            'cid': 205360838,
            'needNewCode': 0,
            'loginUin': account,
            'hostUin': 0,
            'userid': account,
            'reqfrom': 1
          },
          options: Options(followRedirects: false, headers: {
            'Referer': 'https://y.qq.com/',
            'User-Agent': 'Mozilla/5.0',
            'Cookie':
                cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
          }));
      final raw =
          response.data is String ? jsonDecode(response.data) : response.data;
      if (raw is! Map || raw['code'] != 0 || raw['data'] is! Map) {
        final code = raw is Map && raw['code'] is num ? '（${raw['code']}）' : '';
        throw MusicServiceError('QQ音乐网页会话校验未通过$code，请重新认证');
      }
      final data = raw['data'] as Map;
      final creator = data['creator'];
      if (creator is! Map || creator.isEmpty) {
        throw const MusicServiceError('QQ音乐未返回账号资料，请重新认证');
      }
      final reportedIds = ['musicid', 'musicId', 'uin']
          .map((key) => '${creator[key] ?? ''}')
          .where((id) =>
              RegExp(r'^[0-9]+$').hasMatch(id) &&
              id.replaceAll('0', '').isNotEmpty)
          .toSet();
      final aliases = ['uin', 'wxuin', 'qqmusic_uin']
          .map((key) => (cookies[key] ?? '').replaceFirst(RegExp(r'^o0*'), ''))
          .toSet();
      // Official profile responses may mask the creator's numeric ID as 0.
      // Authentication is established by this private endpoint's code=0;
      // compare only real IDs, accepting the platform's QQ/music-ID aliases.
      if (reportedIds.isNotEmpty && !reportedIds.any(aliases.contains)) {
        throw const MusicServiceError('QQ音乐返回账号不一致，请重新认证');
      }
      return creator;
    } on DioException {
      throw const MusicServiceError('QQ音乐账号校验连接失败，请检查网络后重试');
    } on FormatException {
      throw const MusicServiceError('QQ音乐账号校验返回格式异常，请稍后重试');
    }
  }

  Future<void> logout() async {
    ++_profileRevision;
    await channel.invokeMethod<void>('clearSession');
    _cookies = {};
    playlists = [];
    nickname = '';
    avatarUrl = '';
    try { await _profileBox?.deleteAll([profileCacheKey]); } catch (_) {}
    _restored = true;
    _notify();
  }

  static int _csrf(String key) {
    var h = 5381;
    for (final c in key.codeUnits) {
      h = ((h << 5) + h + c) & 0x7fffffff;
    }
    return h;
  }

  Future<Map> rpc(String module, String method, Map<String, dynamic> param,
      {CancelToken? cancelToken, bool auth = false, String? expectedAccount}) async {
    await restore();
    if(expectedAccount != null && account != expectedAccount) throw const MusicServiceError('QQ账号已切换，请刷新后重试');
    return _request(Map.of(_cookies), module, method, param,
        cancelToken: cancelToken, auth: auth);
  }

  Future<Map> _request(Map<String, String> cookies, String module,
      String method, Map<String, dynamic> param,
      {CancelToken? cancelToken, bool auth = false}) async {
    final account = _account(cookies);
    final key = cookies['qqmusic_key'] ?? cookies['qm_keyst'] ?? '';
    final signedIn = account.isNotEmpty && key.isNotEmpty;
    if (auth && !signedIn) throw const MusicServiceError('请先登录QQ音乐');
    final body = {
      'comm': {
        'ct': 24,
        'cv': 4747474,
        'platform': 'yqq.json',
        'g_tk': _csrf(key),
        'g_tk_new_20200303': _csrf(key),
        'need_new_code': 1,
        'format': 'json',
        'uin': account.isEmpty ? '0' : account,
        if (key.isNotEmpty) 'authst': key,
        'tmeLoginType': int.tryParse(cookies['tmeLoginType'] ?? '') ??
            (key.startsWith('W_X') ? 1 : 2)
      },
      'req_0': {'module': module, 'method': method, 'param': param}
    };
    try {
      final response = await client.post<dynamic>(
          'https://u.y.qq.com/cgi-bin/musicu.fcg',
          data: body,
          queryParameters: {
            'g_tk': _csrf(key),
            'g_tk_new_20200303': _csrf(key),
            'needNewCode': 0
          },
          cancelToken: cancelToken,
          options: Options(followRedirects: false, headers: {
            'Referer': 'https://y.qq.com/',
            'User-Agent': 'Mozilla/5.0',
            if (signedIn)
              'Cookie':
                  cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
          }));
      final raw =
          response.data is String ? jsonDecode(response.data) : response.data;
      final item = raw is Map ? raw['req_0'] : null;
      if (raw is! Map ||
          raw['code'] != 0 ||
          item is! Map ||
          item['code'] != 0 ||
          item['data'] is! Map) {
        throw const MusicServiceError('QQ音乐请求未完成，可能需要重新登录或稍后重试');
      }
      final data = item['data'] as Map;
      if (data['code'] is num && data['code'] != 0) {
        throw MusicServiceError('QQ音乐服务暂未完成请求（${data['code']}），请稍后重试');
      }
      return data;
    } on DioException {
      throw const MusicServiceError('QQ音乐连接失败，请检查网络后重试');
    }
  }

  static String clean(Object? value) => '${value ?? ''}'
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&');
  static MediaItem song(Map raw) {
    final mid = '${raw['mid'] ?? raw['songmid'] ?? ''}';
    if (mid.isEmpty) throw const FormatException('QQ song without MID');
    final album = raw['album'] as Map? ?? {};
    final file = raw['file'] as Map? ?? {};
    final singers = raw['singer'] as List? ?? [];
    final albumMid = '${album['mid'] ?? raw['albummid'] ?? ''}';
    final image = albumMid.isEmpty
        ? ''
        : 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg';
    return MediaItem(
        id: 'qq:$mid',
        title: clean(raw['title'] ?? raw['name'] ?? raw['songname']),
        artist:
            singers.whereType<Map>().map((a) => clean(a['name'])).join(' / '),
        album: clean(album['name'] ?? raw['albumname']),
        duration: Duration(seconds: (raw['interval'] as num? ?? 0).toInt()),
        artUri: image.isEmpty ? null : Uri.parse(image),
        extras: {
          'source': 'qq',
          'type': 'qq',
          'mid': mid,
          'qqId': '${raw['id'] ?? raw['songid'] ?? ''}',
          'songType': (raw['type'] as num? ?? 0).toInt(),
          'mediaMid': '${file['media_mid'] ?? ''}',
          'file': Map<String, dynamic>.from(file),
          'image': image,
          'qqArtists': singers
              .whereType<Map>()
              .map((a) => Map<String, dynamic>.from(a))
              .toList(),
          'liked': false
        });
  }

  Future<List<MediaItem>> search(String keyword,
      {int page = 1, int limit = 20}) async {
    final data = await rpc('music.adaptor.SearchAdaptor', 'do_search_v2', {
      'query': keyword,
      'search_type': 0,
      'num_per_page': limit,
      'page_num': page,
      'searchid': '${DateTime.now().microsecondsSinceEpoch}',
      'highlight': 0
    });
    final body = data['body'] as Map? ?? {};
    final result = body['item_song'] as Map? ?? body['song'] as Map? ?? {};
    final items = result['items'] as List? ?? result['list'] as List? ?? [];
    return items.whereType<Map>().map(song).toList();
  }

  Future<QqAudio> audio(MediaItem track, AudioQuality preferred,
      {CancelToken? cancelToken}) async {
    final mid =
        track.extras?['mid'] as String? ?? track.id.replaceFirst('qq:', '');
    final mediaMid = track.extras?['mediaMid'] as String? ?? '';
    final candidates = preferred.fallbacks.toList();
    final attempted = <String>{};
    for (final quality in candidates) {
      final format = switch (quality) {
        AudioQuality.hires => ('RS01', '.flac'),
        AudioQuality.lossless => ('F000', '.flac'),
        AudioQuality.exhigh => ('M800', '.mp3'),
        _ => ('M500', '.mp3')
      };
      if (!attempted.add(format.$1)) continue;
      final filename =
          '${format.$1}${mediaMid.isEmpty ? mid + mid : mediaMid}${format.$2}';
      final data = await rpc(
          'vkey.GetVkeyServer',
          'CgiGetVkey',
          {
            'filename': [filename],
            'guid': '${Random.secure().nextInt(1 << 30)}',
            'songmid': [mid],
            'songtype': [(track.extras?['songType'] as num? ?? 0).toInt()],
            'uin': account.isEmpty ? '0' : account,
            'loginflag': loggedIn ? 1 : 0,
            'platform': '20'
          },
          cancelToken: cancelToken);
      final entries = data['midurlinfo'] as List? ?? [];
      if (entries.isEmpty || entries.first is! Map) continue;
      final item = entries.first as Map;
      final purl = '${item['purl'] ?? ''}';
      if (purl.isEmpty || purl.contains('试听') || purl.startsWith('RS02'))
        continue;
      final sip = (data['sip'] as List? ?? [])
          .whereType<String>()
          .where(
              (u) => Uri.tryParse(u)?.host.endsWith('.qqmusic.qq.com') == true)
          .toList();
      final uri = Uri.tryParse(purl);
      final url = uri?.hasAuthority == true
          ? uri!
          : sip.isNotEmpty
              ? Uri.parse(sip.first).resolve(purl)
              : null;
      if (url == null ||
          !url.host.endsWith('.qqmusic.qq.com') ||
          url.userInfo.isNotEmpty ||
          !['https', 'http'].contains(url.scheme)) continue;
      final basename = url.pathSegments.lastOrNull ?? '';
      final actual = switch (
          basename.substring(0, basename.length < 4 ? basename.length : 4)) {
        'M500' => (AudioQuality.standard, 'mp3'),
        'M800' => (AudioQuality.exhigh, 'mp3'),
        'F000' => (AudioQuality.lossless, 'flac'),
        'RS01' => (AudioQuality.hires, 'flac'),
        _ => null
      };
      if (actual == null) continue;
      return QqAudio(
          url.replace(scheme: 'https').toString(), actual.$1, actual.$2);
    }
    throw const MusicServiceError('QQ音乐暂无可用完整音源，请检查登录、会员权限或切换歌曲');
  }

  Future<(String, String)> lyrics(MediaItem track) async {
    final data =
        await rpc('music.musichallSong.PlayLyricInfo', 'GetPlayLyricInfo', {
      'songMid': track.extras?['mid'],
      'crypt': 0,
      'lrc_t': 0,
      'qrc': 0,
      'qrc_t': 0,
      'trans': 1,
      'trans_t': 0,
      'roma': 0,
      'roma_t': 0,
      'type': 0
    });
    String decode(dynamic value) {
      if (value is! String) return '';
      if (value.contains('[')) return value;
      try {
        return utf8.decode(base64.decode(value));
      } catch (_) {
        return '';
      }
    }

    return (decode(data['lyric']), decode(data['trans']));
  }

  Future<List<SourcePlaylist>> userPlaylists() async {
    await restore();
    final bound = account;
    final data = await rpc('music.musicasset.PlaylistBaseRead',
        'GetPlaylistByUin', {'uin': account},
        auth: true);
    if(account != bound) throw const MusicServiceError('QQ账号已切换，请重新加载歌单');
    final lists = data['v_playlist'] ?? data['playlist'];
    if (lists is! List) throw const MusicServiceError('QQ音乐未返回歌单列表，请重试');
    String playlistId(Map p) {
      for (final field in ['id', 'dissid', 'tid']) {
        final value = '${p[field] ?? ''}';
        if ((BigInt.tryParse(value) ?? BigInt.zero) > BigInt.zero) return value;
      }
      return '';
    }

    playlists = lists
        .whereType<Map>()
        .map((p) => SourcePlaylist(
            source: MusicSource.qq,
            id: playlistId(p),
            directory: '${p['dirId'] ?? p['dirid'] ?? ''}',
            name: clean(
                p['title'] ?? p['dirName'] ?? p['diss_name'] ?? p['name']),
            image: '${p['picurl'] ?? p['picUrl'] ?? p['cover'] ?? ''}',
            count: (p['songNum'] as num? ?? p['songnum'] as num? ?? 0).toInt()))
        .where((p) => p.id.isNotEmpty)
        .toList();
    _notify();
    return playlists;
  }

  Future<List<MediaItem>> playlistSongs(SourcePlaylist list,
      {int page = 1}) async {
    final data = await rpc('music.srfDissInfo.DissInfo', 'CgiGetDiss', {
      'disstid': int.tryParse(list.id) ?? 0,
      'dirid': int.tryParse(list.directory) ?? 0,
      'tag': 1,
      'song_begin': (page - 1) * 100,
      'song_num': 100,
      'userinfo': 1,
      'orderlist': 1,
      'onlysonglist': 0
    });
    if (data['songlist'] is! List)
      throw const MusicServiceError('QQ音乐未返回歌单歌曲，请重试');
    if ((data['songlist'] as List).isEmpty &&
        (data['total_song_num'] as num? ?? 0) > (page - 1) * 100) {
      return _webPlaylistSongs(list, page: page);
    }
    return (data['songlist'] as List).whereType<Map>().map(song).toList();
  }

  Future<List<MediaItem>> _webPlaylistSongs(SourcePlaylist list,
      {required int page}) async {
    try {
      final cookies = Map<String, String>.of(_cookies);
      final response = await client.get<dynamic>(
          'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
          queryParameters: {
            'type': 1,
            'utf8': 1,
            'json': 1,
            'format': 'json',
            'new_format': 1,
            'onlysong': 0,
            'disstid': list.id,
            'loginUin': _account(cookies),
            'hostUin': 0,
            'g_tk': _csrf(key)
          },
          options: Options(followRedirects: false, headers: {
            'Referer': 'https://y.qq.com/n/yqq/playlist',
            'User-Agent': 'Mozilla/5.0',
            if (loggedIn)
              'Cookie':
                  cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')
          }));
      dynamic raw = response.data;
      if (raw is String) {
        final wrapper =
            RegExp(r'^\s*[a-zA-Z_$][\w.$]*\((.*)\);?\s*$', dotAll: true)
                .firstMatch(raw);
        raw = jsonDecode(wrapper?.group(1) ?? raw);
      }
      final lists = raw is Map && raw['code'] == 0 ? raw['cdlist'] : null;
      if (lists is! List || lists.isEmpty || lists.first is! Map) {
        final code = raw is Map && raw['code'] is num ? '（${raw['code']}）' : '';
        throw MusicServiceError('QQ音乐网页歌单读取未完成$code，请重试');
      }
      final info = lists.first as Map;
      // `disstid` is the full playlist TID; legacy `dissid` is a different internal ID.
      final returnedId = '${info['disstid'] ?? ''}';
      final maskedId =
          returnedId.isEmpty || RegExp(r'^0+$').hasMatch(returnedId);
      if (!maskedId && returnedId != list.id)
        throw const MusicServiceError('QQ音乐返回歌单不一致');
      final songs = info['songlist'];
      if (songs is! List ||
          (songs.isEmpty &&
              (info['total_song_num'] as num? ?? info['songnum'] as num? ?? 0) >
                  0)) {
        throw const MusicServiceError('QQ音乐歌单尚未返回歌曲详情，请重试');
      }
      return songs
          .skip((page - 1) * 100)
          .take(100)
          .whereType<Map>()
          .map((item) =>
              song(item['musicData'] is Map ? item['musicData'] as Map : item))
          .toList();
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw MusicServiceError(
          'QQ音乐网页歌单连接失败${status == null ? '' : '（HTTP $status）'}，请重试');
    } on FormatException {
      throw const MusicServiceError('QQ音乐网页歌单返回格式异常，请重试');
    }
  }

  Future<SourcePlaylist> createFavorites() async {
    final old =
        (await userPlaylists()).where((p) => p.name == 'BuYu收藏').toList();
    if (old.isNotEmpty) return old.first;
    final data = await rpc('music.musicasset.PlaylistBaseWrite', 'AddPlaylist',
        {'dirName': 'BuYu收藏'},
        auth: true);
    final result = data['result'] as Map? ?? {};
    if (data['retCode'] != 0 ||
        result['dirId'] == null ||
        result['tid'] == null)
      throw const MusicServiceError('QQ收藏歌单创建未确认，请稍后重试');
    final created = SourcePlaylist(
        source: MusicSource.qq,
        id: '${result['tid']}',
        directory: '${result['dirId']}',
        name: 'BuYu收藏');
    playlists = [...playlists, created];
    _notify();
    return created;
  }

  Future<void> syncFavorite(
      SourcePlaylist list, MediaItem track, bool add, {String? expectedAccount}) async {
    await restore();
    if(expectedAccount != null && account != expectedAccount) throw const MusicServiceError('QQ账号已切换，请刷新后重试');
    final credentials = Map<String, String>.of(_cookies);
    final boundAccount = _account(credentials);
    final detail = await _request(credentials, 'music.pf_song_detail_svr',
        'get_song_detail_yqq', {'song_mid': track.extras?['mid']},
        auth: true);
    final canonical = detail['track_info'];
    final id = canonical is Map ? int.tryParse('${canonical['id']}') : null;
    final songType = canonical is Map ? canonical['type'] : null;
    if (id == null ||
        songType is! int ||
        canonical['mid'] != track.extras?['mid']) {
      throw const MusicServiceError('QQ音乐未确认歌曲身份，请重新搜索后同步');
    }
    final oldType = track.extras?['songType'];
    final data = await _request(
        credentials,
        'music.musicasset.PlaylistDetailWrite',
        add ? 'AddSonglist' : 'DelSonglist',
        {
          'dirId': int.parse(list.directory),
          'tid': int.parse(list.id),
          'bFmtUtf8': true,
          'v_songInfo': [
            {'songId': id, 'songType': songType}
          ]
        },
        auth: true);
    if (data['retCode'] != 0) throw const MusicServiceError('QQ收藏同步未完成，请重试');
    // Older previews used the search result's entity type as the song type.
    // Remove only that exact obsolete entry from the application's own folder.
    if (list.name == 'BuYu收藏' &&
        oldType is int &&
        oldType != songType &&
        '${track.extras?['qqId']}' == '$id') {
      final cleanup = await _request(
          credentials,
          'music.musicasset.PlaylistDetailWrite',
          'DelSonglist',
          {
            'dirId': int.parse(list.directory),
            'tid': int.parse(list.id),
            'bFmtUtf8': true,
            'v_songInfo': [
              {'songId': id, 'songType': oldType}
            ]
          },
          auth: true);
      if (cleanup['retCode'] != 0)
        throw const MusicServiceError('QQ旧版收藏记录尚未清理，请重试');
    }
    // An acknowledgement alone can be stale or represent a no-op. Confirm the
    // requested membership from a fresh cloud read before clearing pending state.
    for (var attempt = 0; attempt < 2; attempt++) {
      var found = false;
      var ended = false;
      for (var page = 1; page <= 100; page++) {
        if (account != boundAccount)
          throw const MusicServiceError('QQ账号已切换，请使用原账号重试');
        final songs = await playlistSongs(list, page: page);
        found = songs.any((song) =>
            song.id == track.id || '${song.extras?['qqId']}' == '$id');
        if (found || songs.length < 100) {
          ended = true;
          break;
        }
      }
      if (ended && found == add) return;
      if (attempt == 0)
        await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    throw const MusicServiceError('QQ音乐尚未确认收藏变更，已保留待同步记录');
  }

  @override
  void dispose() {
    _disposed = true;
    client.close(force: true);
    super.dispose();
  }
}

class QqAudio {
  const QqAudio(this.url, this.quality, this.format);
  final String url, format;
  final AudioQuality quality;
}
