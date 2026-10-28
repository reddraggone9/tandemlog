import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/tandemlog_theme.dart';

Future<void> captureUx(WidgetTester tester, String name) async {
  // Check even without PNG output, so ordinary test runs catch theme drift.
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  expect(
    app.theme,
    tandemlogTheme(app.theme?.brightness ?? Brightness.light),
    reason: 'UX captures must use the production Tandemlog theme.',
  );
  if (app.darkTheme != null) {
    expect(app.darkTheme, tandemlogTheme(Brightness.dark));
  }
  final directory = Platform.environment['TANDEMLOG_UX_CAPTURES'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('ux-root')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> loadUxIcons() async {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final font = File(
      '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await font.exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
      return;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('SDK MaterialIcons not found');
    }
    directory = parent;
  }
}
