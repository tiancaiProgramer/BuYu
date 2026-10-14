import 'dart:ui';

import 'package:flutter/material.dart';

class DisplayMode {
  static const isTv = bool.fromEnvironment('BUJUAN_TV');

  static bool get isWide {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return isTv;
    return useWideLayout(view.physicalSize / view.devicePixelRatio, tv: isTv);
  }

  static bool useWideLayout(Size size, {bool tv = false}) =>
      tv || size.width > size.height;
}

/// Re-evaluates the design scale when a window rotates or enters split screen.
class AdaptiveBujuanApp extends StatefulWidget {
  const AdaptiveBujuanApp({super.key, required this.builder});
  final Widget Function(bool wide) builder;

  @override
  State<AdaptiveBujuanApp> createState() => _AdaptiveBujuanAppState();
}

class _AdaptiveBujuanAppState extends State<AdaptiveBujuanApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    return widget.builder(DisplayMode.useWideLayout(
        view.physicalSize / view.devicePixelRatio,
        tv: DisplayMode.isTv));
  }
}
