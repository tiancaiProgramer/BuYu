// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'simple_extended_image.dart';
import 'adaptive_wallpaper.dart';

/// Keeps the original artwork visible when starting or rotating in landscape.
class SplashArtwork extends StatelessWidget {
  const SplashArtwork(
      {super.key, this.background = '', this.landscapeBackground = ''});

  final String background;
  final String landscapeBackground;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth > constraints.maxHeight;
        final path = wide && landscapeBackground.isNotEmpty
            ? landscapeBackground
            : background;
        if (path.isNotEmpty) {
          if (wide) return AdaptiveWallpaper(portrait: background, landscape: landscapeBackground);
          return SimpleExtendedImage(path,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              fit: wide ? BoxFit.contain : BoxFit.cover);
        }
        if (!wide) {
          return Center(
              child: SvgPicture.asset('assets/images/splash.svg',
                  width: constraints.maxWidth / 1.8, fit: BoxFit.fitWidth));
        }
        return SafeArea(
            child: LayoutBuilder(
                builder: (context, safe) => Center(
                    child: SvgPicture.asset('assets/images/splash.svg',
                        width: safe.maxWidth * .8,
                        height: safe.maxHeight * .78,
                        fit: BoxFit.contain))));
      });
}
