// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

/// Serialize cookie/account writes with explicit logout. Never store credentials here.
class NeteaseSessionWrites {
  static Future<void> _tail = Future.value();
  static Future<void> run(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.catchError((Object _) {});
    return next;
  }
}

const _revision = 'neteaseSessionRevision';
const _authenticated = 'neteaseWasAuthenticated';
const _retried = 'neteaseRecoveryAttempted';
const neteaseOriginalData = 'neteaseOriginalData';
const neteaseOriginalPath = 'neteaseOriginalPath';

DioException _changed(RequestOptions options) =>
    DioException(requestOptions: options, message: '网易云账号状态已变化，请刷新后重试');

/// A late response cannot restore old cookies after logout or an account switch.
class NeteaseSessionCookies extends CookieManager {
  NeteaseSessionCookies(super.cookieJar,
      {required this.revision, required this.authenticated});
  final int Function() revision;
  final bool Function() authenticated;
  bool _current(RequestOptions options) =>
      options.extra[_revision] == revision();

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    options.extra.putIfAbsent(_revision, revision);
    options.extra.putIfAbsent(_authenticated, authenticated);
    try {
      await NeteaseSessionWrites.run(() async {
        if (!_current(options)) throw _changed(options);
        final saved = _SavedRequest();
        super.onRequest(options, saved);
        await saved.done.future;
      });
      if (!_current(options)) throw _changed(options);
      handler.next(options);
    } catch (error) {
      handler.reject(error is DioException
          ? error
          : DioException(
              requestOptions: options, message: '网易云登录状态暂时无法读取，请重试'));
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    try {
      await NeteaseSessionWrites.run(() async {
        if (!_current(response.requestOptions)) return;
        final saved = _SavedResponse();
        super.onResponse(response, saved);
        await saved.done.future;
      });
      handler.next(response);
    } catch (_) {
      handler.reject(DioException(
          requestOptions: response.requestOptions,
          message: '网易云登录状态暂时无法保存，请重试'));
    }
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) async {
    try {
      await NeteaseSessionWrites.run(() async {
        if (!_current(error.requestOptions)) return;
        final saved = _SavedError();
        super.onError(error, saved);
        await saved.done.future;
      });
    } catch (_) {/* Preserve the original transport error. */}
    handler.next(error);
  }
}

// CookieManager's asynchronous persistence is completed through its public handlers.
class _SavedRequest extends RequestInterceptorHandler {
  final done = Completer<void>();
  @override
  void next(RequestOptions options) => done.complete();
  @override
  void reject(DioException error,
          [bool callFollowingErrorInterceptor = false]) =>
      done.completeError(error);
}

class _SavedResponse extends ResponseInterceptorHandler {
  final done = Completer<void>();
  @override
  void next(Response response) => done.complete();
  @override
  void reject(DioException error,
          [bool callFollowingErrorInterceptor = false]) =>
      done.completeError(error);
}

class _SavedError extends ErrorInterceptorHandler {
  final done = Completer<void>();
  @override
  void next(DioException error) => done.complete();
  @override
  void reject(DioException error) => done.complete();
}

enum _Renewal { refreshed, expired, unavailable, changed }

class _RenewalResult {
  const _RenewalResult(this.state, this.revision);
  final _Renewal state;
  final int revision;
}

/// Recover only official authenticated requests, once per request and shared across callers.
class NeteaseSessionRecovery extends Interceptor {
  NeteaseSessionRecovery(
      {required this.dio,
      required this.revision,
      required this.authenticated,
      required this.signature,
      required this.refresh,
      required this.invalidate,
      required this.official,
      DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final Dio dio;
  final int Function() revision;
  final bool Function() authenticated;
  final Future<int> Function(Uri) signature;
  final Future<int> Function() refresh;
  final Future<void> Function(int) invalidate;
  final bool Function(Uri) official;
  final DateTime Function() _now;
  Future<_RenewalResult>? _pending;
  int? _pendingRevision, _lastRevision;
  DateTime? _lastAttempt;
  _RenewalResult? _lastResult;

  bool _eligible(RequestOptions o) =>
      official(o.uri) &&
      !o.extra.containsKey('sessionCookies') &&
      !o.uri.pathSegments
          .any((p) => ['login', 'logout', 'register'].contains(p));

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_eligible(options)) {
      handler.next(options);
      return;
    }
    try {
      options.extra.putIfAbsent(_revision, revision);
      options.extra.putIfAbsent(_authenticated, authenticated);
      if (options.extra[_revision] != revision()) throw _changed(options);
      // POST encryption already captured the cookies actually used in its header.
      options.extra['cookiesHash'] ??= await signature(options.uri);
      if (options.extra[_revision] != revision()) throw _changed(options);
      handler.next(options);
    } catch (error) {
      handler.reject(error is DioException
          ? error
          : DioException(
              requestOptions: options, message: '网易云登录状态暂时无法读取，请重试'));
    }
  }

  Future<_RenewalResult> _renew(int bound) {
    if (_pending != null && _pendingRevision == bound) return _pending!;
    if (_lastRevision == bound &&
        _lastAttempt != null &&
        _lastResult != null &&
        _now().difference(_lastAttempt!) < const Duration(seconds: 30)) {
      return Future.value(_lastResult!);
    }
    final done = Completer<_RenewalResult>();
    _pendingRevision = bound;
    final task = _pending = done.future;
    () async {
      var result = _RenewalResult(_Renewal.unavailable, bound);
      try {
        if (revision() != bound || !authenticated()) {
          result = _RenewalResult(_Renewal.changed, revision());
        } else {
          final code = await refresh();
          if (revision() != bound || !authenticated()) {
            result = _RenewalResult(_Renewal.changed, revision());
          } else if (code == 200) {
            result = _RenewalResult(_Renewal.refreshed, bound);
          } else if (code == 301 || code == 401) {
            await invalidate(bound);
            result = _RenewalResult(_Renewal.expired, revision());
          }
        }
      } catch (_) {
        /* Timeout, parsing and service failures never erase credentials. */
      }
      if (identical(_pending, task)) {
        _lastAttempt = _now();
        _lastRevision = bound;
        _lastResult = result;
        _pending = null;
        _pendingRevision = null;
      }
      done.complete(result);
    }();
    return task;
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final options = response.requestOptions;
    final data = response.data;
    if (!_eligible(options) ||
        data is! Map ||
        '${data['code']}' != '301' ||
        options.extra[_authenticated] != true) {
      handler.next(response);
      return;
    }
    try {
      if (options.extra[_revision] != revision() || !authenticated()) {
        if (_pendingRevision == options.extra[_revision] && _pending != null)
          await _pending;
        // All waiters may report the same confirmed expiry, but never overwrite
        // a newer login or treat an explicit user logout as a network failure.
        if (_lastRevision == options.extra[_revision] &&
            _lastResult?.state == _Renewal.expired &&
            _lastResult?.revision == revision() &&
            !authenticated()) {
          handler.next(response);
          return;
        }
        throw _changed(options);
      }
      if (options.extra[_retried] == true) {
        handler.next(response);
        return;
      }
      if (options.extra['hookRequestData'] == true &&
          !options.extra.containsKey(neteaseOriginalData)) {
        throw DioException(
            requestOptions: options, message: '请求内容无法安全重试，请重新操作');
      }
      var canRetry =
          options.extra['cookiesHash'] != await signature(options.uri);
      if (!canRetry) {
        final result = await _renew(options.extra[_revision] as int);
        if (result.revision != revision() || result.state == _Renewal.changed)
          throw _changed(options);
        if (result.state == _Renewal.expired) {
          handler.next(response);
          return;
        }
        if (result.state == _Renewal.unavailable) {
          // Do not forward the original 301 to account controllers on a transient failure.
          throw DioException(
              requestOptions: options, message: '网易云登录刷新暂未完成，已保留登录，请稍后重试');
        }
        canRetry = true;
      }
      if (options.extra[_revision] != revision() || !authenticated())
        throw _changed(options);
      if (options.cancelToken?.isCancelled == true)
        throw options.cancelToken!.cancelError!;
      if (canRetry) {
        final extra = Map<String, dynamic>.of(options.extra)..[_retried] = true;
        extra.remove('cookiesHash');
        final headers = Map<String, dynamic>.of(options.headers)
          ..removeWhere((name, _) => name.toLowerCase() == 'cookie');
        dynamic body = options.data;
        var path = options.path;
        if (extra.containsKey(neteaseOriginalData)) {
          body = Map.of(extra[neteaseOriginalData] as Map);
          path = extra[neteaseOriginalPath] as String;
          extra.remove('hookRequestDataSuccess');
        }
        final retried = await dio.fetch(options.copyWith(
            path: path, data: body, headers: headers, extra: extra));
        handler.resolve(retried);
        return;
      }
      handler.next(response);
    } on DioException catch (error) {
      handler.reject(error);
    } catch (_) {
      handler.reject(DioException(
          requestOptions: options, message: '网易云登录刷新暂未完成，已保留登录，请稍后重试'));
    }
  }
}
