import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/presentation/workspace_upgrade.dart';
import 'package:tandemlog/storage/workspace_upgrade.dart';

void main() {
  testWidgets(
    'participating installation IDs accept spaces, newlines, commas and semicolons exactly',
    (tester) async {
      const writer = '11111111-1111-4111-8111-111111111111';
      const ids = {
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333',
        '44444444-4444-4444-8444-444444444444',
        '55555555-5555-4555-8555-555555555555',
      };
      final inventory = WorkspaceUpgradeInventory(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        {writer},
        [],
        [],
      );
      WorkspaceUpgradeChoice? choice;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  choice = await showDialog<WorkspaceUpgradeChoice>(
                    context: context,
                    builder: (_) => WorkspaceUpgradeDialog(
                      writer: writer,
                      inventory: inventory,
                      inspect: (_) async => inventory,
                    ),
                  );
                },
                child: const Text('Prepare'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Prepare'));
      await tester.pumpAndSettle();
      final extra = find.byKey(const ValueKey('upgrade-extra-participants'));
      await tester.ensureVisible(extra);
      final list = ids.toList();
      await tester.enterText(
        extra,
        '${list[0]} ${list[1]}\n${list[2]}, ${list[3]}; ${list[0]}',
      );
      final confirmation = find.byKey(
        const ValueKey('upgrade-coordination-confirmation'),
      );
      await tester.ensureVisible(confirmation);
      await tester.tap(confirmation);
      await tester.pump();
      final begin = find.byKey(const ValueKey('begin-workspace-upgrade'));
      await tester.ensureVisible(begin);
      await tester.tap(begin);
      await tester.pumpAndSettle();
      expect(choice?.participants, {writer, ...ids});
      expect(
        choice?.knownOwners,
        isEmpty,
        reason:
            'Participating devices do not silently become historical owners',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
