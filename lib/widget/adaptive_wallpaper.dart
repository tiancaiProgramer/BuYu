// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';

class AdaptiveWallpaper extends StatelessWidget {
  const AdaptiveWallpaper(
      {super.key,
      required this.portrait,
      this.landscape = '',
      this.portraitBlur = 0,
      this.landscapeBlur = 0});
  final String portrait, landscape;
  final double portraitBlur, landscapeBlur;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, size) {
        final wide = size.maxWidth > size.maxHeight;
        final separate = wide && landscape.isNotEmpty;
        final path = separate ? landscape : portrait;
        final blur = separate ? landscapeBlur : portraitBlur;
        if (path.isEmpty) return const SizedBox.expand();
        Widget picture(BoxFit fit) => Image.file(File(path),
            width: size.maxWidth,
            height: size.maxHeight,
            fit: fit,
            cacheWidth: 2048,
            errorBuilder: (_, __, ___) => const SizedBox.expand());
        final image = wide && !separate
            ? Stack(fit: StackFit.expand, children: [
                ClipRect(child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.clamp),
                    child: picture(BoxFit.cover))),
                picture(BoxFit.contain),
              ])
            : picture(BoxFit.cover);
        return blur > 0
            ? ClipRect(
                child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                        sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp),
                    child: image))
            : image;
      });
}
