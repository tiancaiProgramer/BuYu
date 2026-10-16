// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';

/// The existing actions use two columns when the screen is wide, and remain
/// scrollable on short displays or when the user enlarges system text.
class AdaptiveOptionSheet extends StatelessWidget {
  const AdaptiveOptionSheet(
      {super.key, required this.title, required this.children, this.footer});
  final String title;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.scaffoldBackgroundColor;
    final foreground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
            ? Colors.white
            : const Color(0xff333333);
    final accent = theme.brightness == Brightness.dark
        ? const Color(0xffef9a9a)
        : const Color(0xffc84c4a);
    return Theme(
        data: theme.copyWith(
            primaryColor: accent,
            unselectedWidgetColor: foreground.withOpacity(.65),
            iconTheme: theme.iconTheme.copyWith(color: foreground),
            textTheme: theme.textTheme
                .apply(bodyColor: foreground, displayColor: foreground),
            colorScheme: theme.colorScheme.copyWith(
                primary: accent, secondary: accent, onSurface: foreground),
            listTileTheme: ListTileThemeData(
                textColor: foreground, iconColor: foreground)),
        child: DefaultTextStyle.merge(
            style: TextStyle(color: foreground),
            child:
                ColoredBox(color: background, child: Builder(builder: _body))));
  }

  Widget _body(BuildContext context) => SafeArea(
      child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
          child: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(builder: (context, size) {
                    final wide = MediaQuery.sizeOf(context).width >
                        MediaQuery.sizeOf(context).height;
                    final width =
                        wide ? (size.maxWidth - 12) / 2 : size.maxWidth;
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(title,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600))),
                      Wrap(spacing: 12, runSpacing: 8, children: [
                        for (final child in children)
                          SizedBox(
                              width: width,
                              child: Material(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondary
                                      .withOpacity(.5),
                                  clipBehavior: Clip.antiAlias,
                                  child: child)),
                      ]),
                      if (footer != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: footer!),
                    ]);
                  })))));
}
