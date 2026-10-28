// Community maintenance and new features: tiancaiProgramer.
import 'package:flutter/material.dart';
import '../common/app_style.dart';

class BuYuChoiceChip extends StatelessWidget {
  const BuYuChoiceChip(
      {super.key,
      required this.label,
      required this.selected,
      required this.onSelected});
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context),
        fg = BuYuStyle.foreground(Theme.of(context));
    final fill = Color.alphaBlend(
        theme.primaryColor.withOpacity(.14), theme.scaffoldBackgroundColor);
    return ChoiceChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
        backgroundColor: BuYuStyle.surface(theme),
        selectedColor: fill,
        labelStyle: TextStyle(
            fontSize: 14,
            color: selected ? BuYuStyle.action(theme, background: fill) : fg,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
        side: BorderSide(
            color: selected ? theme.primaryColor : Colors.transparent),
        shape: const StadiumBorder(),
        showCheckmark: false,
        pressElevation: 0);
  }
}

/// The same quiet rounded cards as the home page, without a new navigation flow.
class BuYuSettingsList extends StatelessWidget {
  const BuYuSettingsList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    Widget tile(Widget child) => Material(
        color: BuYuStyle.card(Theme.of(context)),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: child);
    final wide =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      final item = children[i];
      if (item is! ListTile) {
        rows.add(item);
        continue;
      }
      if (wide && i + 1 < children.length && children[i + 1] is ListTile) {
        rows.add(IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: tile(item)),
          const SizedBox(width: 12),
          Expanded(child: tile(children[++i]))
        ])));
      } else {
        rows.add(tile(item));
      }
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final row in rows)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: row)
    ]);
  }
}
