// Community maintenance and new features: tiancaiProgramer.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'simple_extended_image.dart';

bool phoneLandscape(BuildContext context) =>
    MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;

const landscapeCardGrid = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    mainAxisExtent: 112,
    mainAxisSpacing: 8,
    crossAxisSpacing: 10);

/// The same cover and text proportions used on the landscape home page.
class LandscapeCard extends StatelessWidget {
  const LandscapeCard(
      {super.key,
      required this.title,
      this.subtitle = '',
      this.image = '',
      this.artwork,
      this.onTap});
  final String title, subtitle, image;
  final Widget? artwork;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => LandscapeCardSurface(
      child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: LayoutBuilder(builder: (context, constraints) {
            final cover = math.min(
                66.0, math.max(32.0, (constraints.maxWidth - 24) * .32));
            return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  SizedBox(
                      width: cover,
                      height: cover,
                      child: artwork ??
                          SimpleExtendedImage(image,
                              width: cover,
                              height: cover,
                              cacheWidth: 256,
                              borderRadius: BorderRadius.circular(8))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, height: 1.2)),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.2,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color
                                      ?.withOpacity(.7))),
                        ],
                      ])),
                ]));
          })));
}

class LandscapeCardSurface extends StatelessWidget {
  const LandscapeCardSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
      color: Theme.of(context).primaryColor.withOpacity(.045),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Center(child: child));
}

/// Keeps existing settings actions and headers, placing two actions in a row.
class AdaptiveSettingsSection extends StatelessWidget {
  const AdaptiveSettingsSection({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    if (!phoneLandscape(context) || children.length < 2) {
      return Column(children: children);
    }
    Widget item(Widget child) => Material(
        color: Theme.of(context).colorScheme.onSecondary.withOpacity(.5),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: child);
    return Column(children: [
      children.first,
      for (var i = 1; i < children.length; i += 2)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Expanded(child: item(children[i])),
                  const SizedBox(width: 12),
                  Expanded(
                      child: i + 1 < children.length
                          ? item(children[i + 1])
                          : const SizedBox.shrink()),
                ]))),
    ]);
  }
}
