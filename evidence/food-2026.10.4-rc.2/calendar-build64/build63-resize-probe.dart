import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/civil_date_input.dart';
import 'file:///tmp/tandemlog-food-date-readability/test/food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  setUpAll(loadSdkRoboto);
  testWidgets('picker selection survives resize across typography fit boundary', (tester) async {
    final controller = TextEditingController(text: '2026-10-15');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    try {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2), padding: const EdgeInsets.only(top: 24,bottom: 48)), child: child!),
        home: Scaffold(body: CivilDateInput(controller: controller, label: 'Expiration')),
      ));
      await tester.tap(find.byTooltip('Choose Expiration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('17'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 800);
      await tester.binding.setSurfaceSize(const Size(390, 800));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(controller.text, '2026-10-17');
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });
}
