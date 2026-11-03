import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/domain/event.dart' show FormatFailure;
import 'package:tandemlog/main.dart';

import '../integration_test/profile_fixture.dart';
import 'section_navigation_host_test.dart' as host;

/// A folder whose history can't be opened, with a chosen failure.
class _FailingFolder extends host.FaultingFolder {
  _FailingFolder(super.delegate, this.failure);
  final Object failure;
  @override
  Future<Uint8List> readBounded(String name, int limit) async {
    if (name.endsWith('.applog')) throw failure;
    return super.readBounded(name, limit);
  }
}

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;

  Future<void> open(WidgetTester tester, Object failure) async {
    final data = (await tester.runAsync(host.fixture))!;
    addTearDown(() => tester.runAsync(() => data.root.delete(recursive: true)));
    await tester.runAsync(
      () => seedNativeProfile(data.profile, {
        'folder': data.folder.location,
        'user': data.user,
        'appearance': 'dark',
      }),
    );
    await tester.pumpWidget(
      TandemlogApp(
        profilePath: data.profile,
        folderFactory: (_) => _FailingFolder(data.folder, failure),
        textEngineFactory: host.createHostTextEngine,
        timeSourceFactory: host.createHostTimeSource,
      ),
    );
    await host.ready(
      tester,
      () =>
          find.byKey(const ValueKey('workspace-opening')).evaluate().isEmpty &&
          find.byType(FilledButton).evaluate().isNotEmpty,
    );
  }

  testWidgets('newer data asks for an update, details collapsed', (
    tester,
  ) async {
    const message =
        'Unknown app event food.future. Update the app; history was preserved.';
    await open(tester, FormatFailure(message));
    expect(find.text('Update Tandemlog'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
    // Plain words first; the exact message only behind Technical details.
    expect(find.text(message), findsNothing);
    expect(find.textContaining('A little less to remember'), findsNothing);
    expect(find.textContaining('Can’t open'), findsNothing);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Copy'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('another open failure is a folder failure, not onboarding', (
    tester,
  ) async {
    await open(tester, FormatFailure('App history record is damaged.'));
    expect(find.text('Can’t open your data folder'), findsOneWidget);
    // Nothing is open, so there is no count to show.
    expect(find.textContaining(' open'), findsNothing);
    expect(find.textContaining('A little less to remember'), findsNothing);
    expect(find.textContaining('folder sync whenever'), findsNothing);
    expect(find.text('Update Tandemlog'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
