// Community maintenance and new features: tiancaiProgramer.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const wideAccent = Color(0xff83e0d0);

class RemoteFocusStyle extends InheritedTheme {
  const RemoteFocusStyle(
      {super.key,
      required super.child,
      required this.color,
      required this.fill,
      required this.selection});
  final Color color, fill, selection;
  static RemoteFocusStyle? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RemoteFocusStyle>();
  @override
  bool updateShouldNotify(RemoteFocusStyle old) =>
      color != old.color || fill != old.fill || selection != old.selection;
  @override
  Widget wrap(BuildContext context, Widget child) => RemoteFocusStyle(
      color: color, fill: fill, selection: selection, child: child);
}

ThemeData wideTheme() => ThemeData.dark(useMaterial3: false).copyWith(
      scaffoldBackgroundColor: const Color(0xff111923),
      colorScheme: const ColorScheme.dark(primary: wideAccent),
      visualDensity: VisualDensity.standard,
    );

/// One focus target per action; touch and D-pad activate the same callback.
class RemoteButton extends StatefulWidget {
  const RemoteButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.autofocus = false,
    this.selected = false,
    this.focusNode,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.onFocusChanged,
  });

  final Widget child;
  final FutureOr<void> Function()? onPressed;
  final bool autofocus;
  final bool selected;
  final FocusNode? focusNode;
  final EdgeInsets padding;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<RemoteButton> createState() => _RemoteButtonState();
}

class _RemoteButtonState extends State<RemoteButton> {
  bool _focused = false;
  bool _running = false;

  Future<void> _activate() async {
    if (_running || widget.onPressed == null) return;
    _running = true;
    try {
      await widget.onPressed!();
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          // A held OK key must not repeatedly open pages or replace the queue.
          if (event is KeyRepeatEvent &&
              [
                LogicalKeyboardKey.enter,
                LogicalKeyboardKey.select,
                LogicalKeyboardKey.space,
                LogicalKeyboardKey.gameButtonA
              ].contains(event.logicalKey)) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: _focused
              ? RemoteFocusStyle.of(context)?.fill ?? const Color(0xff254b50)
              : widget.selected
                  ? RemoteFocusStyle.of(context)?.selection ??
                      const Color(0xff253540)
                  : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: _focused
                    ? RemoteFocusStyle.of(context)?.color ?? wideAccent
                    : Colors.transparent,
                width: 2),
          ),
          child: InkWell(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(12),
            onFocusChange: (focused) {
              setState(() => _focused = focused);
              widget.onFocusChanged?.call(focused);
              if (focused) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    Scrollable.ensureVisible(context,
                        duration: const Duration(milliseconds: 120),
                        alignment: .5);
                  }
                });
              }
            },
            onTap: widget.onPressed == null ? null : _activate,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      );
}

class RemoteInputScope extends StatelessWidget {
  const RemoteInputScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        },
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: child,
        ),
      );
}
