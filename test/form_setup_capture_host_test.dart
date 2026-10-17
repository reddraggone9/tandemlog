import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:tandemlog/platform/android_section_navigation.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/local_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/presentation/name_entry_dialog.dart';
import 'section_navigation_host_test.dart' as host;
import 'food_expiry_guidance_test.dart' show loadSdkRoboto;

void main() {
  host.nativeHostLibraryPath = Platform.environment['TANDEMLOG_TEXT_LIBRARY']!;
  setUpAll(loadSdkRoboto);
  testWidgets(
    'capture floating label clears fixed action through review at420px200percent',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 900);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final data = (await tester.runAsync(() => host.fixture()))!;
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: data.profile,
          textEngineFactory: host.createHostTextEngine,
          timeSourceFactory: host.createHostTimeSource,
        ),
      );
      await host.ready(
        tester,
        () => find.text('Synthetic section task').evaluate().isNotEmpty,
      );
      final resources = host.hostResources(tester);
      try {
        final prefix = (await tester.runAsync(
          () => host.canonical(data.folder),
        ))!;
        await tester.tap(find.byKey(const ValueKey('open-capture')));
        await tester.pumpAndSettle();
        final capture = find.widgetWithText(TextField, 'What needs doing?');
        final action = find.byKey(const ValueKey('capture-add'));
        expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
        expect(tester.widget<TextField>(capture).decoration!.errorText, isNull);
        final actionElement = tester.element(action);
        final neutralRect = tester.getRect(action);
        Rect paintedLabelRect() {
          final label = find.descendant(
            of: capture,
            matching: find.text('What needs doing?'),
          );
          expect(label, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: label, matching: find.byType(RichText)),
          );
          expect(paragraph.text.toPlainText(), 'What needs doing?');
          return MatrixUtils.transformRect(
            paragraph.getTransformTo(null),
            Offset.zero & paragraph.size,
          );
        }

        void expectSeparateLabel() {
          expect(
            paintedLabelRect().top,
            greaterThanOrEqualTo(tester.getRect(action).bottom + 4),
            reason:
                'The painted floating label needs a visible gap below the action',
          );
        }

        expectSeparateLabel();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(capture).decoration!.errorText,
          'Enter at least one task title.',
        );
        final editable = tester.widget<EditableText>(
          find.descendant(of: capture, matching: find.byType(EditableText)),
        );
        expect(editable.focusNode.hasFocus, isTrue);
        expect(identical(tester.element(action), actionElement), isTrue);
        expect(tester.getRect(action), neutralRect);
        expectSeparateLabel();
        expect(
          (await tester.runAsync(() => host.canonical(data.folder)))!,
          prefix,
        );
        await tester.enterText(capture, 'Synthetic corrected capture');
        await tester.pumpAndSettle();
        expect(tester.getRect(action), neutralRect);
        expectSeparateLabel();
        expect(
          find.descendant(of: action, matching: find.text('Review errors')),
          findsOneWidget,
        );
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(capture).decoration!.errorText, isNull);
        expect(
          find.descendant(of: action, matching: find.text('Add')),
          findsOneWidget,
        );
        expect(tester.getRect(action), neutralRect);
        expectSeparateLabel();
        expect(
          (await tester.runAsync(() => host.canonical(data.folder)))!,
          prefix,
          reason: 'Review of the corrected capture cannot create a task',
        );
        expect(
          tester.widget<TextField>(capture).controller!.text,
          'Synthetic corrected capture',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await host.waitForHostShutdown(tester, resources);
        await tester.runAsync(() => data.root.delete(recursive: true));
      }
    },
  );
  testWidgets(
    'setup and capture reveal local errors without appending and save valid input once',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('synthetic-validation-host-'),
      ))!;
      await tester.pumpWidget(
        TandemlogApp(
          profilePath: root.path,
          textEngineFactory: host.createHostTextEngine,
          timeSourceFactory: host.createHostTimeSource,
        ),
      );
      await host.ready(
        tester,
        () =>
            find.widgetWithText(FilledButton, 'Start').evaluate().isNotEmpty &&
            tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Start'),
                    )
                    .onPressed !=
                null,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      final name = find.widgetWithText(TextField, 'Your name');
      await host.ready(
        tester,
        () =>
            name.evaluate().isNotEmpty &&
            tester.widget<TextField>(name).enabled == true,
      );
      final resources = host.hostResources(tester);
      final state = tester.state(find.byType(TasksPage)) as dynamic;
      final store = state.store;
      final prefix = (await tester.runAsync(
        () => host.canonical(store.folder),
      ))!;
      expect(tester.widget<TextField>(name).decoration!.errorText, isNull);
      final setupActionRect = tester.getRect(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(name).decoration!.errorText,
        'Enter your name.',
      );
      expect(tester.widget<TextField>(name).focusNode!.hasFocus, isTrue);
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Review errors')),
        setupActionRect,
        reason: 'Revealing setup errors must not move the action',
      );
      expect(
        (await tester.runAsync(() => host.canonical(store.folder)))!,
        prefix,
      );
      final nameController = tester.widget<TextField>(name).controller!;
      nameController.value = const TextEditingValue(
        text: 'Candidate name',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 9),
      );
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review errors'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(nameController.value.composing, const TextRange(start: 0, end: 9));
      expect(
        tester.widget<TextField>(name).decoration!.errorText,
        'Finish entering your name before continuing.',
      );
      expect(
        (await tester.runAsync(() => host.canonical(store.folder)))!,
        prefix,
      );
      await tester.enterText(name, 'Synthetic person');
      await tester.pump();
      expect(find.text('Review errors'), findsOneWidget);
      await tester.tap(find.text('Review errors'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(() => host.canonical(store.folder)))!,
        prefix,
      );
      await tester.tap(find.text('Continue'));
      await host.ready(
        tester,
        () =>
            find.text('No open tasks').evaluate().isNotEmpty &&
            state.busy == false,
      );
      await tester.tap(find.byKey(const ValueKey('open-capture')));
      await tester.pumpAndSettle();
      final capture = find.widgetWithText(TextField, 'What needs doing?');
      final beforeCapture = (await tester.runAsync(
        () => host.canonical(store.folder),
      ))!;
      expect(tester.widget<TextField>(capture).decoration!.errorText, isNull);
      final captureActionRect = tester.getRect(
        find.byKey(const ValueKey('capture-add')),
      );
      await tester.tap(find.byKey(const ValueKey('capture-add')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(capture).decoration!.errorText,
        'Enter at least one task title.',
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('capture-add'))),
        captureActionRect,
        reason: 'Capture Review errors stays at the original action position',
      );
      expect(
        (await tester.runAsync(() => host.canonical(store.folder)))!,
        beforeCapture,
      );
      await tester.enterText(capture, 'Synthetic task A\nSynthetic task B');
      await tester.pump();
      await tester.tap(find.text('Review errors'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(() => host.canonical(store.folder)))!,
        beforeCapture,
      );
      await tester.tap(find.byKey(const ValueKey('capture-add')));
      await host.ready(
        tester,
        () =>
            (state.rows as List)
                .where((dynamic row) => row['kind'] == 'task')
                .length ==
            2,
      );
      expect(tester.widget<TextField>(capture).controller!.text, '');
      expect(
        tester.widget<TextField>(capture).decoration!.errorText,
        isNull,
        reason: 'Successful capture resets pristine state for the next draft',
      );
      await tester.pumpWidget(const SizedBox());
      await host.waitForHostShutdown(tester, resources);
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );

  testWidgets(
    'new-user dialog is neutral, reveals empty-name error, retains text and guards repeated submit',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => const NameEntryDialog(
                      title: 'Create user',
                      label: 'Name',
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      expect(tester.widget<TextField>(input).decoration!.errorText, isNull);
      final actionRect = tester.getRect(
        find.widgetWithText(FilledButton, 'Create user'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create user'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input).decoration!.errorText,
        'Enter a name.',
      );
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Review errors')),
        actionRect,
        reason: 'Revealing a name error must not move the action',
      );
      expect(result, isNull);
      final controller = tester.widget<TextField>(input).controller!;
      controller.value = const TextEditingValue(
        text: 'Candidate name',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 9),
      );
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review errors'),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(controller.value.composing, const TextRange(start: 0, end: 9));
      expect(
        tester.widget<TextField>(input).decoration!.errorText,
        'Finish entering your name before creating this user.',
      );
      await tester.enterText(input, 'Synthetic user');
      await tester.pump();
      await tester.tap(find.text('Review errors'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      final submit = tester.widget<TextField>(input).onSubmitted!;
      submit('Synthetic user');
      submit('Synthetic user');
      await tester.pumpAndSettle();
      expect(result, 'Synthetic user');
      expect(find.text('Open'), findsOneWidget);
    },
  );
  for (final dirty in [false, true]) {
    testWidgets(
      'native section request defers behind owned Task help; dirty=$dirty',
      (tester) async {
        const channel = MethodChannel('tandemlog/validation-help-host-test');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => null);
        final data = (await tester.runAsync(() => host.fixture()))!;
        try {
          await tester.pumpWidget(
            TandemlogApp(
              profilePath: data.profile,
              textEngineFactory: host.createHostTextEngine,
              timeSourceFactory: host.createHostTimeSource,
              sectionNavigation: AndroidSectionNavigation(channel: channel),
            ),
          );
          await host.ready(
            tester,
            () => find.text('Synthetic section task').evaluate().isNotEmpty,
          );
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          await tester.tap(find.text('Synthetic section task'));
          await host.ready(
            tester,
            () => find.byType(TaskEditor).evaluate().isNotEmpty,
          );
          if (dirty) {
            await tester.enterText(
              find.widgetWithText(TextField, 'Title'),
              'Private synthetic draft',
            );
            await tester.pump();
          }
          await tester.tap(find.byTooltip('Task field help'));
          await tester.pumpAndSettle();
          final before = (await tester.runAsync(
            () => host.canonical(data.folder),
          ))!;
          final done = Completer<void>();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .handlePlatformMessage(
                channel.name,
                const StandardMethodCodec().encodeMethodCall(
                  const MethodCall('openSection', {'id': 1, 'section': 'food'}),
                ),
                (_) => done.complete(),
              );
          await done.future;
          await tester.pumpAndSettle();
          expect(find.text('Task field help'), findsOneWidget);
          expect(
            tester.state<TaskEditorState>(find.byType(TaskEditor)).closeBusy,
            isTrue,
          );
          expect(state.foodVisible, isFalse);
          expect(state.settings.lastSection, AppSection.tasks);
          await tester.tap(find.text('Done'));
          if (dirty) {
            await host.ready(
              tester,
              () => find.text('Unsaved changes').evaluate().isNotEmpty,
            );
            await tester.tap(
              find.descendant(
                of: find.byType(AlertDialog).last,
                matching: find.widgetWithText(TextButton, 'Cancel'),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byType(TaskEditor), findsOneWidget);
            expect(find.text('Private synthetic draft'), findsOneWidget);
            expect(state.foodVisible, isFalse);
            expect(state.settings.lastSection, AppSection.tasks);
          } else {
            await host.ready(
              tester,
              () => state.foodVisible == true && state.sectionWork == null,
            );
            expect(find.byType(TaskEditor), findsNothing);
            expect(find.text('Task field help'), findsNothing);
            expect(state.settings.lastSection, AppSection.food);
          }
          expect(
            (await tester.runAsync(() => host.canonical(data.folder)))!,
            before,
          );
        } finally {
          if (find.text('Unsaved changes').evaluate().isNotEmpty) {
            await tester.tap(
              find.descendant(
                of: find.byType(AlertDialog).last,
                matching: find.widgetWithText(TextButton, 'Cancel'),
              ),
            );
            await tester.pumpAndSettle();
          }
          final resources = host.hostResources(tester);
          final closingState = tester.state(find.byType(TasksPage)) as dynamic;
          await tester.pumpWidget(const SizedBox());
          await host.ready(
            tester,
            () =>
                closingState.sectionWork == null &&
                closingState.syncing == null,
            settle: false,
          );
          await host.waitForHostShutdown(tester, resources);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
          await tester.runAsync(() => data.root.delete(recursive: true));
        }
      },
    );
  }
}
