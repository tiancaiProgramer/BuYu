import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_drawer/flutter_zoom_drawer.dart';

void main() {
  testWidgets(
      'avatar action works on first launch and drawer closes on main tap',
      (tester) async {
    final controller = ZoomDrawerController();
    await tester.pumpWidget(MaterialApp(
      home: ZoomDrawer(
        controller: controller,
        angle: 0,
        mainScreenScale: 0,
        duration: const Duration(milliseconds: 20),
        mainScreenTapClose: true,
        menuScreen: const Text('Menu'),
        mainScreen: Center(
          child: ElevatedButton(
            onPressed: () => controller.open!(),
            child: const Text('Open menu'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    expect(controller.isOpen!(), isTrue);
    await tester.tap(find.text('Open menu'));
    await tester.pumpAndSettle();
    expect(controller.isOpen!(), isFalse);
  });
}
