// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'package:flutter/material.dart';
import 'remote_button.dart';

class WideArtwork extends StatelessWidget {
  const WideArtwork({super.key, required this.url, required this.size});
  final String url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
        width: size,
        height: size,
        color: const Color(0xff283b43),
        child: Icon(Icons.music_note, size: size * .45, color: wideAccent));
    if (url.isEmpty) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(10), child: placeholder);
    }
    final image = url.startsWith('http')
        ? Image.network(url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder)
        : Image.file(File(url),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder);
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: image);
  }
}
