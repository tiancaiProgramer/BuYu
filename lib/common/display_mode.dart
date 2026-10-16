// Community maintenance and new features: tiancaiProgramer.
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DisplayMode {
  static SystemUiOverlayStyle overlayForBackground(Color background) {
    final light = ThemeData.estimateBrightnessForColor(background) == Brightness.light;
    return (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
        .copyWith(statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false);
  }

  static Future<void> applyOrientation(bool enabled, {bool tv = isTv}) =>
      SystemChrome.setPreferredOrientations(tv
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : enabled
              ? DeviceOrientation.values
              : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  static const isTv = bool.fromEnvironment('BUJUAN_TV');

  static const _display = MethodChannel('bujuan/display');
  static EdgeInsets physicalCutout = EdgeInsets.zero;

  static Future<EdgeInsets?> readCutout() async {
    try {
      final values =
          await _display.invokeMapMethod<String, dynamic>('getCutoutInsets');
      if (values == null) return null;
      double side(String key) => (values[key] as num?)?.toDouble() ?? 0;
      return EdgeInsets.fromLTRB(
          side('left'), side('top'), side('right'), side('bottom'));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static MediaQueryData safeMedia(MediaQueryData data, double ratio) {
    final native = physicalCutout / ratio;
    EdgeInsets maximum(EdgeInsets a, EdgeInsets b) => EdgeInsets.fromLTRB(
        math.max(a.left, b.left),
        math.max(a.top, b.top),
        math.max(a.right, b.right),
        math.max(a.bottom, b.bottom));
    final available = EdgeInsets.fromLTRB(
        math.max(0, native.left - data.viewInsets.left),
        math.max(0, native.top - data.viewInsets.top),
        math.max(0, native.right - data.viewInsets.right),
        math.max(0, native.bottom - data.viewInsets.bottom));
    return data.copyWith(
        padding: maximum(data.padding, available),
        viewPadding: maximum(data.viewPadding, native),
        textScaleFactor: 1.0);
  }

  static bool get isWide {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return isTv;
    return useWideLayout(view.physicalSize / view.devicePixelRatio, tv: isTv);
  }

  static bool useWideLayout(Size size, {bool tv = false}) =>
      tv || size.width > size.height;

  static Size designSize(Size size, {bool tv = isTv}) {
    if (tv) return const Size(2339, 1080);
    if (size.width <= size.height) return const Size(750, 1334);
    // Use the same short-edge scale as portrait for icons and touch targets.
    return Size(size.width / size.height * 750, 750);
  }

  static Size get windowSize {
    final view = PlatformDispatcher.instance.implicitView;
    return view == null
        ? const Size(390, 844)
        : view.physicalSize / view.devicePixelRatio;
  }
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
  int _request = 0;
  Future<void> _refreshCutout() async {
    final revision = ++_request;
    final insets = await DisplayMode.readCutout();
    if (!mounted ||
        revision != _request ||
        insets == null ||
        insets == DisplayMode.physicalCutout) return;
    setState(() => DisplayMode.physicalCutout = insets);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCutout());
  }

  @override
  void didChangeMetrics() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshCutout());
  }

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
