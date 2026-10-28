// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'unified_library.dart';

/// Owns foreground polling/retries; durable changes live in UnifiedLibrary.
class FavoritesAutoSync with WidgetsBindingObserver {
  FavoritesAutoSync(this.library,
      {this.interval = const Duration(minutes: 5),
      this.retryDelays = const [
        Duration(seconds: 10),
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
        Duration(minutes: 5)
      ]});
  final UnifiedLibrary library;
  final Duration interval;
  final List<Duration> retryDelays;
  Timer? _periodic, _retry;
  Future<void>? _running;
  bool _started = false, _disposed = false, _foreground = true;
  int _attempt = 0;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    library.addListener(_changed);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _poll();
    unawaited(check());
  }

  void _poll() {
    _periodic?.cancel();
    if (_foreground)
      _periodic = Timer.periodic(interval, (_) => unawaited(check()));
  }

  void _changed() {
    if (_disposed ||
        !_foreground ||
        _running != null ||
        library.syncing ||
        library.refreshing) return;
    if (library.hasRetryableWork) {
      _scheduleRetry();
    } else {
      _retry?.cancel();
      _retry = null;
      _attempt = 0;
    }
  }

  void _scheduleRetry() {
    if (_retry?.isActive == true || retryDelays.isEmpty) return;
    final index = _attempt.clamp(0, retryDelays.length - 1);
    _attempt++;
    _retry = Timer(retryDelays[index], () {
      _retry = null;
      unawaited(check());
    });
  }

  Future<void> check() {
    if (_disposed) return Future<void>.value();
    if (_running != null) return _running!;
    _retry?.cancel();
    _retry = null;
    final done = Completer<void>();
    _running = done.future;
    () async {
      try {
        await library.reconcile();
      } catch (_) {
        // Keep persisted operations; a lifecycle trigger or timer retries them.
      } finally {
        _running = null;
        if (!_disposed && _foreground) {
          if (library.hasRetryableWork) {
            _scheduleRetry();
          } else {
            _attempt = 0;
          }
        }
        done.complete();
      }
    }();
    return done.future;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _attempt = 0;
      _poll();
      unawaited(check());
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final wasForeground = _foreground;
      _foreground = false;
      _periodic?.cancel();
      _retry?.cancel();
      _retry = null;
      if (wasForeground) unawaited(check());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _periodic?.cancel();
    _retry?.cancel();
    if (_started) {
      library.removeListener(_changed);
      WidgetsBinding.instance.removeObserver(this);
    }
  }
}
