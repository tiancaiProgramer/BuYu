import 'package:bujuan/common/appearance_store.dart';
import 'package:bujuan/widget/adaptive_wallpaper.dart';
import 'package:bujuan/widget/app_bar.dart';
import 'package:flutter/material.dart';
import '../home/home_controller.dart';

class ImageBlur extends StatefulWidget {
  const ImageBlur({super.key, required this.path, this.landscape = false});
  final String path;
  final bool landscape;

  @override
  State<ImageBlur> createState() => _ImageBlurState();
}

class _ImageBlurState extends State<ImageBlur> {
  double blur = 0;
  bool saving = false;

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await AppearanceStore(Home.to.box).importImage(
          ArtworkKind.wallpaper, widget.path,
          wide: widget.landscape, blur: blur);
      Home.to.refreshBackground();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图片保存失败，请重新选择')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final preview = Center(
        child: AspectRatio(
            aspectRatio: wide ? 16 / 9 : 9 / 16,
            child: AdaptiveWallpaper(
                portrait: widget.path,
                landscape: widget.landscape ? widget.path : '',
                portraitBlur: blur,
                landscapeBlur: blur)));
    final controls = Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('模糊程度'),
      Slider(
          value: blur,
          min: 0,
          max: 10,
          onChanged: saving ? null : (value) => setState(() => blur = value)),
      TextButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? '保存中…' : '保存')),
    ]);
    return Scaffold(
        appBar: MyAppBar(title: Text(widget.landscape ? '横屏背景' : '竖屏 / 通用背景')),
        body: SafeArea(
            child: wide
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Expanded(flex: 3, child: preview),
                      const SizedBox(width: 20),
                      Expanded(
                          flex: 2,
                          child: SingleChildScrollView(child: controls)),
                    ]))
                : Column(children: [Expanded(child: preview), controls])));
  }
}
