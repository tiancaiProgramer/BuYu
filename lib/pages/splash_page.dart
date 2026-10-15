import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:bujuan/widget/splash_artwork.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/adapters.dart';

import '../common/constants/key.dart';
import '../routes/router.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return SplashPageState();
  }
}

class SplashPageState extends State<SplashPage> {
  double opacity = 0;
  double scale = 1;
  Duration duration = const Duration(milliseconds: 1000);
  Duration durationFinish = const Duration(milliseconds: 1000);
  bool isFinish = false;
  Map<String, dynamic>? mapData;
  bool noFirst = false;
  String splashBg = '';
  String splashBgLandscape = '';
  Timer? _navigation;
  Box box = GetIt.instance<Box>();

  // final OnAudioQuery onAudioQuery = GetIt.instance<OnAudioQuery>();

  @override
  void initState() {
    super.initState();
    splashBg = box.get(splashBackgroundSp, defaultValue: '');
    splashBgLandscape = box.get(splashBackgroundLandscapeSp, defaultValue: '');
    // noFirst = Home.to.box.get(noFirstOpen);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        statusBarBrightness:
            Get.isPlatformDarkMode ? Brightness.dark : Brightness.light,
        statusBarIconBrightness:
            Get.isPlatformDarkMode ? Brightness.light : Brightness.dark,
      ));
      _navigation = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) AutoRouter.of(context).replaceNamed(Routes.home);
      });
    });
  }

  @override
  void dispose() {
    _navigation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SplashArtwork(
          background: splashBg, landscapeBackground: splashBgLandscape),
    );
  }
}
