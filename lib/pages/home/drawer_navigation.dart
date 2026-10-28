// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';

/// Route changes must wait for the actual close animation, not a fixed delay.
Future<bool> closeDrawerForNavigation(ZoomDrawerController drawer,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final state = drawer.stateNotifier;
  if (state == null || state.value == DrawerState.closed) {
    drawer.close?.call();
    return true;
  }
  final closed = Completer<bool>();
  void changed() {
    if (state.value == DrawerState.closed && !closed.isCompleted) {
      closed.complete(true);
    }
  }
  state.addListener(changed);
  try {
    drawer.close?.call();
    changed();
    return await closed.future.timeout(timeout, onTimeout: () => false);
  } finally {
    state.removeListener(changed);
  }
}
