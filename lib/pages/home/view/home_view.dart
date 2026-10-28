import '../../../common/display_mode.dart';
import '../../tv/tv_home.dart';
import '../../tv/tv_player.dart';
import '../../user/personal_landscape.dart';
import 'phone_landscape_player.dart';
import '../../wide/wide_playback.dart';
import '../../wide/remote_button.dart';
import 'package:flutter/services.dart';

import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/home/view/body_view.dart';
import 'package:bujuan/pages/home/view/panel_view.dart';
import 'package:bujuan/widget/swipeable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';
import 'package:get/get.dart';

import '../../../widget/simple_extended_image.dart';
import '../../../widget/weslide/panel.dart';
import 'menu_view.dart';

class _PhonePanel extends StatefulWidget {
  const _PhonePanel();
  @override
  State<_PhonePanel> createState() => _PhonePanelState();
}

class _PhonePanelState extends State<_PhonePanel> {
  WidePlayback? _playback;
  int? _tab;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width <= MediaQuery.sizeOf(context).height) {
      _tab = null;
      return const PanelView();
    }
    _playback ??= WidePlayback.connect(Home.to);
    _tab ??= Home.to.second.value ? Home.to.selectIndex.value : 2;
    return Obx(() {
      final theme = Theme.of(context);
      final colors = Home.to.playbackColors(context);
      final foreground = ThemeData.estimateBrightnessForColor(
                  Color.lerp(colors.first, colors.last, .5)!) ==
              Brightness.dark
          ? Colors.white
          : Colors.black.withOpacity(.75);
      final backgroundLuminance = Color.lerp(colors.first, colors.last, .5)!.computeLuminance();
      final accentLuminance = theme.primaryColor.computeLuminance();
      final contrast = (accentLuminance > backgroundLuminance
          ? (accentLuminance + .05) / (backgroundLuminance + .05)
          : (backgroundLuminance + .05) / (accentLuminance + .05));
      final accent = contrast >= 3 ? theme.primaryColor : foreground;
      return Theme(
          data: theme.copyWith(
              primaryColor: accent,
              iconTheme: theme.iconTheme.copyWith(color: foreground),
              textTheme: theme.textTheme
                  .apply(bodyColor: foreground, displayColor: foreground)),
          child: RemoteFocusStyle(
              color: accent,
              fill: accent.withOpacity(.12),
              selection: accent.withOpacity(.06),
              child: RemoteInputScope(
                  child: AnnotatedRegion<SystemUiOverlayStyle>(
                      value: DisplayMode.overlayForBackground(colors.first),
                      child: AnimatedContainer(
                          key: const ValueKey('landscape-player-background'),
                          duration: const Duration(milliseconds: 300),
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  colors: colors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomCenter)),
                          child: SafeArea(
                              child: Stack(children: [
                            Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                                child: FadeTransition(
                                    opacity: Home.to.animationPanel,
                                    child: Row(children: [
                                      Expanded(
                                          child: _tab == 2
                                              ? PhoneLandscapePlayer(
                                                  playback: _playback!,
                                                  perform: (action) async {
                                                    try {
                                                      await action();
                                                    } catch (_) {
                                                      if (mounted)
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                                const SnackBar(
                                                                    content: Text(
                                                                        '操作未完成，请稍后重试')));
                                                    }
                                                  })
                                              : Column(children: [
                                                  Expanded(
                                                      child:
                                                          Home.to.pages[_tab!]),
                                                  TvControls(
                                                      playback: _playback!,
                                                      compact: true,
                                                      perform: (action) =>
                                                          action()),
                                                ])),
                                      SizedBox(
                                          width: 52,
                                          child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceEvenly,
                                              children: [
                                                for (var i = 0; i < 4; i++)
                                                  RemoteButton(
                                                      key: ValueKey(
                                                          'phone-player-tab:$i'),
                                                      selected: _tab == i,
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      onPressed: () {
                                                        Home.to.selectIndex
                                                            .value = i;
                                                        setState(
                                                            () => _tab = i);
                                                      },
                                                      child: Icon(
                                                          [
                                                            TablerIcons.atom_2,
                                                            TablerIcons
                                                                .playlist,
                                                            TablerIcons.quote,
                                                            TablerIcons
                                                                .message_2
                                                          ][i],
                                                          size: 22)),
                                              ])),
                                    ]))),
                            Positioned(
                                top: 0,
                                left: 0,
                                child: IconButton(
                                    key: const ValueKey('phone-player-close'),
                                    constraints: const BoxConstraints.tightFor(
                                        width: 36, height: 36),
                                    padding: const EdgeInsets.all(6),
                                    onPressed: () =>
                                        Home.to.panelControllerHome.close(),
                                    icon: const Icon(
                                        Icons.keyboard_arrow_down_sharp,
                                        size: 24))),
                          ])))))));
    });
  }

  @override
  void dispose() {
    _playback?.dispose();
    super.dispose();
  }
}

class HomeView extends GetView<Home> {
  final Widget? body;

  const HomeView({
    Key? key,
    this.body,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    controller.buildContext = context;
    final screen = MediaQuery.sizeOf(context);
    final wide = screen.width > screen.height;
    // Our bundled ZoomDrawer paints its first shadow 20px before the main page.
    // Reserve the cutout in both the menu and the page translation so the
    // controls stay centred in the usable solid area, before either shadow.
    const shadowWidth = 20.0;
    final menuContentWidth = (screen.shortestSide * .256 - shadowWidth)
        .clamp(48.0, double.infinity)
        .toDouble();
    final menuWidth = menuContentWidth + MediaQuery.paddingOf(context).left;
    final drawerSlide =
        wide ? menuWidth + shadowWidth : screen.shortestSide * .24;
    final bottomHeight = MediaQuery.viewPaddingOf(context).bottom;
    return Material(
        child: DisplayMode.isTv
            ? const TvHome()
            : ZoomDrawer(
                moveMenuScreen: false,
                menuScreen: const MenuView(),
                mainScreen: Obx(() {
                  final started = controller.showPlaybackControls;
                  final wide = MediaQuery.sizeOf(context).width >
                      MediaQuery.sizeOf(context).height;
                  return SlidingUpPanel(
                    color: Colors.transparent,
                    parallaxEnabled: true,
                    parallaxOffset: .03,
                    controller: controller.panelControllerHome,
                    onPanelSlide: (value) =>
                        controller.changeSlidePosition(value),
                    boxShadow: const [
                      BoxShadow(
                          blurRadius: 8.0, color: Color.fromRGBO(0, 0, 0, 0.05))
                    ],
                    isDraggable: started,
                    panelBuilder: () => started
                        ? const _PhonePanel()
                        : const SizedBox.shrink(),
                    body: body ?? const BodyView(),
                    minHeight: !started ? 0 : wide
                        ? (started ? 44 : 0) +
                            MediaQuery.viewPaddingOf(context).bottom
                        : controller.portraitMiniContentHeight +
                            bottomHeight +
                            controller.panelAlbumPadding * 2,
                    maxHeight: started ? Get.height : 0,
                    header: _buildHeader(context, bottomHeight),
                  );
                }),
                dragOffset: 360.w,
                angle: 0,
                menuBackgroundColor: Theme.of(context).cardColor,
                slideWidth: drawerSlide,
                menuScreenWidth: wide ? menuWidth : null,
                mainScreenScale: 0,
                duration: const Duration(milliseconds: 200),
                reverseDuration: const Duration(milliseconds: 200),
                showShadow: true,
                mainScreenTapClose: true,
                menuScreenTapClose: true,
                androidCloseOnBackTap: true,
                drawerShadowsBackgroundColor: Colors.grey,
                controller: controller.myDrawerController,
              ));
  }

  Widget _buildHeader(context, bottomHeight) {
    if (!controller.showPlaybackControls) return const SizedBox.shrink();
    if (MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height) {
      return Obx(() {
        final started = controller.showPlaybackControls;
        final open = controller.panelOpenPositionThan1.value;
        if (open) return const SizedBox.shrink();
        if (!started) return const SizedBox.shrink();
        // Constrain the header before applying camera/gesture insets. The
        // panel positions its header without a horizontal constraint.
        return SizedBox(
            width: MediaQuery.sizeOf(context).width,
            child: Material(
                key: const ValueKey('phone-mini-player-surface'),
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SafeArea(
                    top: false,
                    child: SizedBox(
                        height: 44,
                    child: InkWell(
                        key: const ValueKey('phone-mini-player'),
                        onTap: () => controller.panelControllerHome.open(),
                        child: Padding(
                            padding: const EdgeInsets.only(
                                left: 12,
                                right: PersonalLandscape.playlistRightInset),
                            child: Row(children: [
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SimpleExtendedImage(
                                      controller.mediaItem.value
                                              .extras?['image'] ??
                                          '',
                                      width: 30,
                                      height: 30)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(
                                      '${controller.mediaItem.value.title} · ${controller.mediaItem.value.artist ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 16))),
                              IconButton(
                                  key: const ValueKey('phone-mini-toggle'),
                                  onPressed: () => controller.playOrPause(),
                                  icon: Icon(
                                      controller.playing.value
                                          ? TablerIcons.player_pause
                                          : TablerIcons.player_play,
                                      size: 25)),
                            ])))))));
      });
    }
    return AnimatedBuilder(
      animation: controller.animationController,
      builder: (context, child) {
        return Stack(
          children: [
            Container(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top *
                      controller.slideSecondPosition.value),
              child: child,
            ),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: controller.panelAlbumPadding),
              margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
              height: controller.panelTopSize *
                  controller.animationController.value,
              width: 750.w,
              child: Obx(() => Visibility(
                    visible: !controller.second.value &&
                        controller.panelOpenPositionThan1.value,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () =>
                              controller.panelControllerHome.close(),
                          icon: Obx(() => Icon(Icons.keyboard_arrow_down_sharp,
                              color: controller.bodyColor.value)),
                        ),
                        Text(
                          'Now Playing',
                          style: TextStyle(
                              color: controller.bodyColor.value,
                              fontSize: 28.sp),
                        ),
                      ],
                    ),
                  )),
            ),
          ],
        );
      },
      child: Obx(() => GestureDetector(
            onVerticalDragEnd: (controller.second.value) ? (e) {} : null,
            child: Swipeable(
                background: const SizedBox.shrink(),
                child: InkWell(
                  key: const ValueKey('portrait-mini-player'),
                  child: Container(
                    width: MediaQuery.sizeOf(context).width,
                    padding: EdgeInsets.all(controller.panelAlbumPadding),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        _buildMediaTitle(context),
                        _buildAlbum(),
                      ],
                    ),
                  ),
                  onTap: () {
                    if (controller.panelControllerHome.isPanelClosed) {
                      controller.panelControllerHome.open();
                    } else {
                      if (controller.panelController.isPanelOpen)
                        controller.panelController.close();
                    }
                  },
                ),
                onSwipeLeft: () =>
                    controller.audioServeHandler.skipToPrevious(),
                onSwipeRight: () => controller.audioServeHandler.skipToNext()),
          )),
    );
  }

  //构建歌曲标题和播放按钮
  Widget _buildMediaTitle(context) {
    return Obx(() => Visibility(
          visible: !controller.panelOpenPositionThan1.value,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: Container(
                      padding: EdgeInsets.only(
                          left: controller.panelMobileMinSize +
                              controller.panelAlbumPadding),
                      alignment: Alignment.centerLeft,
                      height: controller.portraitMiniContentHeight,
                      child: Obx(
                        () => RichText(
                          key: const ValueKey('portrait-mini-title'),
                          text: TextSpan(
                              text: '${Home.to.mediaItem.value.title} - ',
                              children: [
                                TextSpan(
                                    text: Home.to.mediaItem.value.artist ?? '',
                                    style: TextStyle(
                                        fontSize: 24.sp,
                                        fontWeight: FontWeight.w500))
                              ],
                              style: TextStyle(
                                  fontSize: 32.sp,
                                  color: controller.second.value
                                      ? controller.bodyColor.value
                                      : controller.getLightTextColor(context),
                                  fontWeight: FontWeight.w500)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))),
              IconButton(
                  key: const ValueKey('portrait-mini-toggle'),
                  onPressed: () => controller.playOrPause(),
                  icon: Obx(() => Icon(
                        controller.playing.value
                            ? TablerIcons.player_pause
                            : TablerIcons.player_play,
                        color: controller.second.value
                            ? controller.bodyColor.value
                            : controller.getLightTextColor(context),
                        size: 44.sp,
                      ))),
            ],
          ),
        ));
  }

  //构建歌曲专辑
  Widget _buildAlbum() {
    return AnimatedBuilder(
      animation: controller.animationController,
      builder: (context, index) {
        return Container(
          margin: EdgeInsets.only(
              left: (750.w - 630.w - controller.panelAlbumPadding * 2) /
                  2 *
                  controller.animationController.value,
              top: (controller.panelTopSize +
                      MediaQuery.of(context).padding.top -
                      controller.panelAlbumPadding) *
                  controller.animationController.value),
          width: controller.panelMobileMinSize +
              550.w * controller.animationController.value,
          height: controller.panelMobileMinSize +
              550.w * controller.animationController.value,
          child: index,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(controller.panelMobileMinSize / 2),
        child: Obx(() => SimpleExtendedImage(
              '${Home.to.mediaItem.value.extras?['image'] ?? ''}?param=500y500',
              width: 630.w,
              height: 630.w,
            )),
      ),
    );
  }

  Widget _buildHeaderL(context, bottomHeight) {
    // return Obx(() => IgnorePointer(
    //       ignoring: controller.panelOpenPositionThan8.value,
    //       child: AnimatedBuilder(
    //         animation: controller.animationController,
    //         builder: (context, child) {
    //           return Container(
    //             height: controller.panelMobileMinSize +
    //                 controller.panelAlbumPadding * 2 +
    //                 (Get.width/8*3*.86 - controller.panelMobileMinSize + controller.panelAlbumPadding * 2) * controller.animationController.value,
    //             alignment: Alignment.centerLeft,
    //             child: child,
    //           );
    //         },
    //         child: InkWell(
    //           child: Container(
    //             width: Get.width,
    //             padding: EdgeInsets.symmetric(horizontal: controller.panelAlbumPadding),
    //             child: Stack(
    //               alignment: Alignment.centerLeft,
    //               children: [
    //                 _buildMediaTitleL(context),
    //                 _buildAlbumL(),
    //               ],
    //             ),
    //           ),
    //           onTap: () {
    //             controller.panelControllerHome.open();
    //           },
    //         ),
    //       ),
    //     ));
    return Obx(() => IgnorePointer(
          ignoring: controller.panelOpenPositionThan8.value,
          child: AnimatedBuilder(
            animation: controller.animationController,
            builder: (context, child) {
              return Container(
                height: controller.panelMobileMinSize +
                    controller.panelAlbumPadding * 2 +
                    (Get.width / 8 * 3 * .86 -
                            controller.panelMobileMinSize +
                            controller.panelAlbumPadding * 2) *
                        controller.animationController.value,
                alignment: Alignment.centerLeft,
                child: child,
              );
            },
            child: InkWell(
              child: Container(
                width: Get.width,
                padding: EdgeInsets.symmetric(
                    horizontal: controller.panelAlbumPadding),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    _buildMediaTitleL(context),
                    _buildAlbumL(),
                  ],
                ),
              ),
              onTap: () {
                controller.panelControllerHome.open();
              },
            ),
          ),
        ));
  }

  //构建歌曲标题和播放按钮
  Widget _buildMediaTitleL(context) {
    return Obx(() => Visibility(
          visible: !controller.panelOpenPositionThan1.value,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                  child: Container(
                      padding: EdgeInsets.only(
                          left: controller.panelMobileMinSize +
                              controller.panelAlbumPadding),
                      alignment: Alignment.centerLeft,
                      height: controller.panelMobileMinSize,
                      child: Obx(
                        () => RichText(
                          textScaleFactor: 1.0,
                          text: TextSpan(
                              text: '${Home.to.mediaItem.value.title} - ',
                              children: [
                                TextSpan(
                                    text: Home.to.mediaItem.value.artist ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500))
                              ],
                              style: TextStyle(
                                  color: Home.to.second.value
                                      ? Home.to.bodyColor.value
                                      : Home.to.getLightTextColor(context),
                                  fontWeight: FontWeight.bold)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))),
              IconButton(
                  onPressed: () =>
                      controller.audioServeHandler.skipToPrevious(),
                  icon: const Icon(
                    Icons.skip_previous,
                  )),
              IconButton(
                  onPressed: () => controller.playOrPause(),
                  icon: Obx(() => Icon(
                        controller.playing.value
                            ? Icons.pause
                            : Icons.play_arrow,
                      ))),
              IconButton(
                  onPressed: () => controller.audioServeHandler.skipToNext(),
                  icon: const Icon(
                    Icons.skip_next_rounded,
                  ))
            ],
          ),
        ));
  }

  //构建歌曲专辑
  Widget _buildAlbumL() {
    double albumWidth = Get.width / 8 * 3 * .86;
    double leftWidth = Get.width / 8 * 3;
    return AnimatedBuilder(
      animation: controller.animationController,
      builder: (context, index) {
        return Container(
          margin: EdgeInsets.only(
              left:
                  (leftWidth - albumWidth - controller.panelAlbumPadding * 2) /
                      2 *
                      controller.animationController.value,
              top: controller.panelMobileMinSize *
                  controller.animationController.value),
          width: controller.panelMobileMinSize +
              (albumWidth - controller.panelMobileMinSize) *
                  controller.animationController.value,
          height: controller.panelMobileMinSize +
              (albumWidth - controller.panelMobileMinSize) *
                  controller.animationController.value,
          child: index,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(controller.panelMobileMinSize / 2),
        child: Obx(() => SimpleExtendedImage(
              '${Home.to.mediaItem.value.extras?['image'] ?? ''}?param=800y800',
              width: albumWidth,
              height: albumWidth,
            )),
      ),
    );
  }
}

class LeftMenu {
  String title;
  IconData icon;
  String path;
  String pathUrl;

  LeftMenu(this.title, this.icon, this.path, this.pathUrl);
}
