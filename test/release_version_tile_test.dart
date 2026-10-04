import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/release_version_tile.dart';

void main() {
  for (final version in ['2026.10.1', '2026.10.2-rc.1']) {
    testWidgets('shows and copies only release version $version', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReleaseVersionTile(version: version)),
        ),
      );
      expect(find.text('Version'), findsOneWidget);
      expect(find.text(version), findsOneWidget);
      expect(find.textContaining('build'), findsNothing);
      await tester.tap(find.byTooltip('Copy version'));
      await tester.pumpAndSettle();
      final copy = calls.where((c) => c.method == 'Clipboard.setData').single;
      expect(copy.arguments, {'text': version});
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(
        tester.getSize(find.byTooltip('Copy version')).width,
        greaterThanOrEqualTo(48),
      );
    });
  }

  testWidgets('missing metadata does not copy a guessed version', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReleaseVersionTile(version: null)),
      ),
    );
    expect(find.text('Unavailable'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
  });

  testWidgets('clipboard failure is contextual and can be retried', (
    tester,
  ) async {
    var fail = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData' && fail) {
          throw PlatformException(
            code: 'denied',
            message: 'private diagnostic',
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReleaseVersionTile(version: '2026.10.2-rc.1')),
      ),
    );
    await tester.tap(find.byTooltip('Copy version'));
    await tester.pumpAndSettle();
    expect(find.text('Could not copy version. Try again.'), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
    expect(tester.takeException(), isNull);
    fail = false;
    await tester.tap(find.byTooltip('Copy version'));
    await tester.pumpAndSettle();
    expect(find.text('Could not copy version. Try again.'), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
