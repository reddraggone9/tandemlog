import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'profile_fixture.dart';

/// Choosing another user from the top-right menu shows that user's tasks right
/// away, without another rebuild (Lee 2026-11-03, seen on Windows rc.1).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerUserSwitchRefreshTests();
}

void registerUserSwitchRefreshTests() {
  testWidgets('switching user re-renders the Tasks list', (tester) async {
    final root = await Directory.systemTemp.createTemp('user-switch-');
    final data = await Directory('${root.path}/data').create();
    final profile = await Directory('${root.path}/profile').create();
    final folder = LocalLogFolder(data.path);
    final alex = const Uuid().v4(), sam = const Uuid().v4();
    final seed = await openNativeFixtureStore(folder, '${root.path}/seed');
    await seed.command(alex, 'user.created', {'name': 'Synthetic Alex'});
    await seed.command(sam, 'user.created', {'name': 'Synthetic Sam'});
    await seed.createNativeFixtureTask(const Uuid().v4(), {
      'title': 'Alex only task',
      'description': '',
      'assignee': alex,
    });
    await seed.createNativeFixtureTask(const Uuid().v4(), {
      'title': 'Sam only task',
      'description': '',
      'assignee': sam,
    });
    await seed.close();
    await seedNativeProfile(profile.path, {'folder': data.path, 'user': alex});
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Finder menuItem(String name) =>
        find.widgetWithText(CheckedPopupMenuItem<String>, name);
    await tester.pumpWidget(TandemlogApp(profilePath: profile.path));
    await tester.pumpAndSettle();
    expect(find.text('Alex only task'), findsOneWidget);
    expect(find.text('Sam only task'), findsNothing);

    await tester.tap(find.byTooltip('Active user: Synthetic Alex'));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('Synthetic Sam'));
    // Settle only; nothing else may trigger a rebuild of the list.
    await tester.pumpAndSettle();
    expect(find.byTooltip('Active user: Synthetic Sam'), findsOneWidget);
    expect(find.text('Sam only task'), findsOneWidget);
    expect(find.text('Alex only task'), findsNothing);

    await tester.tap(find.byTooltip('Active user: Synthetic Sam'));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('Synthetic Alex'));
    await tester.pumpAndSettle();
    expect(find.text('Alex only task'), findsOneWidget);
    expect(find.text('Sam only task'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await root.delete(recursive: true);
  });
}
