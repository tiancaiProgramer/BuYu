import 'package:auto_route/auto_route.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../common/constants/platform_utils.dart';
import '../../../widget/simple_extended_image.dart';
import '../../../widget/adaptive_wallpaper.dart';

class BodyView extends GetView<Home> {
  const BodyView({Key? key, this.child}) : super(key: key);
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    controller.buildContext = context;
    final bottomHeight = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Home.to.landscape ? Colors.transparent : null,
      body: Stack(
        children: [
          Positioned.fill(
              child: Obx(() => AdaptiveWallpaper(
                  portrait: controller.background.value,
                  landscape: controller.backgroundLandscape.value,
                  portraitBlur: controller.backgroundBlur.value,
                  landscapeBlur: controller.backgroundLandscapeBlur.value))),
          Obx(() {
            final started = controller.showPlaybackControls;
            return Padding(
              padding: EdgeInsets.only(
                  bottom: !started
                      ? MediaQuery.viewPaddingOf(context).bottom
                      : wide
                          ? 44 + MediaQuery.viewPaddingOf(context).bottom
                          : controller.portraitMiniContentHeight +
                              bottomHeight +
                              controller.panelAlbumPadding * 2),
              child: SafeArea(
                  top: false,
                  bottom: false,
                  left: wide,
                  right: wide,
                  child: LayoutBuilder(
                      builder: (context, constraints) => MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              size: wide
                                  ? constraints.biggest
                                  : MediaQuery.sizeOf(context)),
                          child: child ?? const AutoRouter()))),
            );
          }),
        ],
      ),
    );
  }
}

class BodyViewL extends GetView<Home> {
  const BodyViewL({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    controller.buildContext = context;
    double bottomHeight =
        MediaQuery.of(controller.buildContext).padding.bottom *
            (PlatformUtils.isIOS ? 0.6 : 0.85);
    if (bottomHeight == 0) bottomHeight = 25.w;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Home.to.landscape ? Colors.transparent : null,
      body: Stack(
        children: [
          Obx(() => Visibility(
                visible: controller.background.value.isNotEmpty,
                child: SimpleExtendedImage(
                  Home.to.mediaItem.value.extras?['image'] ?? '',
                  fit: BoxFit.cover,
                  width: Get.width,
                  height: Get.height,
                ),
              )),
          Padding(
            padding: EdgeInsets.only(
                bottom: controller.panelMobileMinSize +
                    controller.panelAlbumPadding * 2),
            child: const AutoRouter(),
          )
        ],
      ),
    );
  }
}
