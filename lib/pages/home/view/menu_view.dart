import 'package:auto_route/auto_route.dart';
import 'package:bujuan/pages/home/home_controller.dart';
import 'package:bujuan/pages/user/user_controller.dart';
import 'package:bujuan/routes/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../widget/simple_extended_image.dart';

class MenuView extends GetView<Home> {
  const MenuView({super.key});

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    Widget action(int index, {bool fill = false}) => IconButton(
          key: ValueKey('menu-action:$index'),
          constraints: fill ? const BoxConstraints.expand() : null,
          tooltip: controller.leftMenus[index].title,
          onPressed: () {
            if (!Home.to.landscape) controller.myDrawerController.close!();
            Future.delayed(const Duration(milliseconds: 200), () {
              if (controller.leftMenus[index].path.isEmpty) {
                Home.to.sleep(context);
                return;
              }
              if (controller.leftMenus[index].pathUrl.isEmpty) {
                context.router.pushNamed(controller.leftMenus[index].path);
                return;
              }
              context.router.replaceNamed(controller.leftMenus[index].path);
            });
          },
          icon: Obx(() => Icon(controller.leftMenus[index].icon,
              size: 52.sp,
              color: controller.currPathUrl.value ==
                      controller.leftMenus[index].pathUrl
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).scaffoldBackgroundColor)),
        );
    return SafeArea(
        // This drawer is on the left; a right-side camera inset belongs to
        // the main page and must not shift the drawer contents to the left.
        right: !wide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(padding: EdgeInsets.symmetric(vertical: wide ? 6 : 25.w)),
            GestureDetector(
              key: const ValueKey('menu-avatar'),
              child: Obx(() => SimpleExtendedImage.avatar(
                    '${controller.userData.value.profile?.avatarUrl ?? ''}?param=300y300',
                    width: 90.w,
                  )),
              onTap: () {
                if (controller.loginStatus.value == LoginStatus.noLogin) {
                  context.router.pushNamed(Routes.login);
                  return;
                }
                if (!Home.to.landscape) controller.myDrawerController.close!();
                Future.delayed(const Duration(milliseconds: 200), () {
                  context.router.pushNamed(Routes.userSetting);
                });
              },
            ),
            if (wide) const SizedBox(height: 24),
            Expanded(
                child: wide
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: LayoutBuilder(
                          key: const ValueKey('landscape-menu-actions'),
                          builder: (context, constraints) {
                            final count = controller.leftMenus.length;
                            final minimum = (52.sp + 16).clamp(
                                kMinInteractiveDimension, double.infinity);
                            if (constraints.maxHeight >= minimum * count) {
                              // Like the right shortcuts, each action occupies an
                              // equal share of the space below the avatar.
                              return Column(children: [
                                for (var i = 0; i < count; i++)
                                  Expanded(child: action(i, fill: true)),
                              ]);
                            }
                            // Keep every control reachable in a short split window.
                            return ListView.builder(
                              padding: EdgeInsets.zero,
                              itemExtent: minimum.toDouble(),
                              itemCount: count,
                              itemBuilder: (_, i) => action(i, fill: true),
                            );
                          },
                        ))
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(vertical: 140.w),
                        itemCount: controller.leftMenus.length,
                        itemBuilder: (_, index) => Padding(
                            padding: EdgeInsets.symmetric(vertical: 12.w),
                            child: action(index)),
                      )),
          ],
        ));
  }
}

class MenuViewL extends GetView<Home> {
  const MenuViewL({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160.w,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(padding: EdgeInsets.symmetric(vertical: 35.w)),
            GestureDetector(
              child: Obx(() => SimpleExtendedImage.avatar(
                    '${controller.userData.value.profile?.avatarUrl ?? ''}?param=300y300',
                    width: 90.w,
                  )),
              onTap: () {
                if (controller.loginStatus.value == LoginStatus.noLogin) {
                  context.router.pushNamed(Routes.login);
                  return;
                }
                if (!Home.to.landscape) controller.myDrawerController.close!();
                Future.delayed(const Duration(milliseconds: 200), () {
                  context.router.pushNamed(Routes.userSetting);
                });
              },
            ),
            Expanded(
                child: ListView.builder(
              padding: EdgeInsets.symmetric(vertical: 40.w),
              itemCount: controller.leftMenus.length,
              itemBuilder: (context1, index) => InkWell(
                child: Container(
                  height: 120.w,
                  margin: EdgeInsets.only(bottom: 20.w),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                          child: Obx(
                        () => Icon(controller.leftMenus[index].icon,
                            size: 54.w,
                            color: controller.currPathUrl.value ==
                                    controller.leftMenus[index].pathUrl
                                ? Theme.of(context).primaryColor
                                : Theme.of(context).iconTheme.color),
                      )),
                      Obx(() => Visibility(
                            visible: controller.currPathUrl.value ==
                                controller.leftMenus[index].pathUrl,
                            child: Container(
                              margin: EdgeInsets.only(top: 10.w),
                              decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  borderRadius: BorderRadius.circular(6.w)),
                              height: 54.w,
                              width: 6.w,
                            ),
                          ))
                    ],
                  ),
                ),
                onTap: () {
                  if (!Home.to.landscape)
                    controller.myDrawerController.close!();
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (controller.leftMenus[index].path.isEmpty) {
                      Home.to.sleep(context);
                      return;
                    }
                    if (controller.leftMenus[index].pathUrl.isEmpty) {
                      context.router
                          .pushNamed(controller.leftMenus[index].path);
                      return;
                    }
                    context.router
                        .replaceNamed(controller.leftMenus[index].path);
                  });
                },
              ),
            )),
          ],
        ),
      ),
    );
  }
}
