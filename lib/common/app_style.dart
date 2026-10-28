// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';

/// Shared controls use the page palette. cardColor remains the inverse drawer.
class BuYuStyle {
  static double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
  }

  static Color foreground(ThemeData theme) {
    final background = theme.scaffoldBackgroundColor;
    final preferred = theme.textTheme.bodyLarge?.color;
    if (preferred != null && contrast(preferred, background) >= 4.5)
      return preferred;
    return background.computeLuminance() < .4
        ? Colors.white
        : const Color(0xff333333);
  }

  static Color surface(ThemeData theme) => Color.alphaBlend(
      foreground(theme).withOpacity(.035), theme.scaffoldBackgroundColor);
  static Color card(ThemeData theme) => Color.alphaBlend(
      theme.primaryColor.withOpacity(.045), theme.scaffoldBackgroundColor);

  /// Retain the theme's hue while making small action labels readable.
  static Color action(ThemeData theme, {Color? background}) {
    final bg = background ?? theme.scaffoldBackgroundColor;
    final target = bg.computeLuminance() < .4 ? Colors.white : Colors.black;
    var color = theme.primaryColor;
    for (var i = 1; contrast(color, bg) < 4.5 && i <= 20; i++) {
      color = Color.lerp(theme.primaryColor, target, i / 20)!;
    }
    return color;
  }

  static ThemeData components(ThemeData base) {
    final fg = foreground(base), bg = base.scaffoldBackgroundColor;
    final panel = surface(base), accent = action(base, background: panel);
    final body = base.textTheme.bodyMedium!.copyWith(color: fg, fontSize: 16);
    final title = body.copyWith(fontSize: 18, fontWeight: FontWeight.w600);
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    Color control(Set<MaterialState> states) =>
        states.contains(MaterialState.disabled)
            ? fg.withOpacity(.3)
            : states.contains(MaterialState.selected)
                ? accent
                : fg.withOpacity(.6);
    return base.copyWith(
      popupMenuTheme: PopupMenuThemeData(
          color: panel, textStyle: body, shape: shape, elevation: 6),
      dialogTheme: DialogTheme(
          backgroundColor: panel,
          shape: shape,
          titleTextStyle: title,
          contentTextStyle: body),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: bg,
          modalBackgroundColor: bg,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          clipBehavior: Clip.antiAlias),
      textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
              foregroundColor: MaterialStateProperty.resolveWith((states) =>
                  states.contains(MaterialState.disabled)
                      ? fg.withOpacity(.35)
                      : accent),
              minimumSize: const MaterialStatePropertyAll(Size(48, 44)),
              textStyle: const MaterialStatePropertyAll(
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              shape: MaterialStatePropertyAll(shape))),
      checkboxTheme: CheckboxThemeData(
          fillColor: MaterialStateProperty.resolveWith(control),
          checkColor: const MaterialStatePropertyAll(Colors.white)),
      radioTheme:
          RadioThemeData(fillColor: MaterialStateProperty.resolveWith(control)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      chipTheme: base.chipTheme.copyWith(
          backgroundColor: panel,
          selectedColor: base.primaryColor.withOpacity(.14),
          labelStyle: body.copyWith(fontSize: 14),
          secondaryLabelStyle: body.copyWith(fontSize: 14, color: accent),
          side: const BorderSide(color: Colors.transparent),
          shape: const StadiumBorder()),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
          labelStyle: body.copyWith(fontSize: 14),
          counterStyle: body.copyWith(fontSize: 12),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: fg.withOpacity(.3))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent, width: 1.5))),
      textSelectionTheme: TextSelectionThemeData(
          cursorColor: accent,
          selectionColor: base.primaryColor.withOpacity(.2),
          selectionHandleColor: accent),
      listTileTheme: base.listTileTheme.copyWith(
          textColor: fg,
          iconColor: fg,
          titleTextStyle: body,
          subtitleTextStyle:
              body.copyWith(fontSize: 14, color: fg.withOpacity(.8))),
      appBarTheme: base.appBarTheme.copyWith(
          titleTextStyle: title,
          iconTheme: IconThemeData(color: fg),
          actionsIconTheme: IconThemeData(color: fg)),
      tabBarTheme: base.tabBarTheme.copyWith(
          labelColor: action(base),
          unselectedLabelColor: fg.withOpacity(.75),
          indicatorColor: base.primaryColor),
    );
  }
}
