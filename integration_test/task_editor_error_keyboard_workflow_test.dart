import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tandemlog/main.dart';
import 'package:tandemlog/platform/folder_actions.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'package:tandemlog/storage/log_folder.dart';
import 'package:uuid/uuid.dart';

import 'native_text_fixtures.dart';
import 'task_flow_test.dart' as flows;

class _FailingPicker extends FolderActions {
  int calls = 0;
  @override
  bool get requiresPicker => true;
  @override
  Future<String?> pick() async {
    calls++;
    // Match the Android adapter's translated recoverable launch diagnostic.
    throw StateError('Could not open the folder picker. Try again.');
  }

  @override
  Future<bool> canOpen(String location) async => false;
}

void registerTaskEditorErrorKeyboardTests() {
  for (final configuration in [
    ('light', true),
    ('light', false),
    ('dark', true),
    ('dark', false),
  ]) {
    final appearance = configuration.$1;
    final withError = configuration.$2;
    testWidgets(
      'Tasks title and actions survive retained picker error at 320dp 200% $appearance ${withError ? 'retained-error' : 'clean'}',
      (tester) async {
        final root = await Directory.systemTemp.createTemp('task-error-ime-');
        final folder = await Directory('${root.path}/shared').create();
        final profile = await Directory('${root.path}/profile').create();
        final seed = await openNativeFixtureStore(
          LocalLogFolder(folder.path),
          '${root.path}/seed',
        );
        final user = const Uuid().v4(), task = const Uuid().v4();
        await seed.command(user, 'user.created', {
          'name': 'Synthetic household',
        });
        await seed.createTasks({task: 'RC68 capture edited'}, user);
        await seed.close();
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': folder.path,
            'user': user,
            'appearance': appearance,
          }),
        );
        Future<Map<String, List<int>>> canonical() async => {
          for (final file in folder.listSync().whereType<File>())
            file.path: file.readAsBytesSync(),
        };
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        // Native GTK execution with Android Material targets and the exact
        // captured phone metrics; this is not an actual Android keyboard run.
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.view.resetViewPadding();
          tester.view.resetPadding();
          tester.view.resetViewInsets();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          debugDefaultTargetPlatformOverride = null;
        });
        final picker = _FailingPicker();
        await tester.pumpWidget(
          TandemlogApp(profilePath: profile.path, folderActions: picker),
        );
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(TasksPage)) as dynamic;
        final before = await canonical();
        final originalStore = state.store;
        try {
          // The clean control and actual source picker-error path share the
          // exact Android-captured logical viewport, text scale and IME inset.
          if (withError) {
            await flows.openSettings(tester);
            final choose = find.widgetWithText(
              TextButton,
              'Use a different folder',
            );
            await tester.ensureVisible(choose);
            await tester.pumpAndSettle();
            expect(choose.hitTestable(), findsOneWidget);
            await tester.tap(choose);
            await tester.pumpAndSettle();
            expect(picker.calls, 1);
            expect(state.choosingFolder, false);
            expect(state.busy, false);
            expect(state.error, contains('Could not open the folder picker'));
          }
          await flows.selectTask(tester, task, control: false);
          final editor = tester.state<TaskEditorState>(find.byType(TaskEditor));
          final title = find.byKey(const ValueKey('title'));
          await tester.ensureVisible(title);
          await tester.pumpAndSettle();
          await tester.tap(title);
          await tester.pumpAndSettle();
          final editableFinder = find.descendant(
            of: title,
            matching: find.byType(EditableText),
          );
          final editable = tester.state<EditableTextState>(editableFinder);
          final controller = editable.widget.controller;
          final originalText = controller.text;
          final textSession = state.editingText;
          final saveCommand = state.textSaveCommand;
          tester.view.padding = const FakeViewPadding(top: 24);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await tester.pumpAndSettle();
          expect(
            tester.state<TaskEditorState>(find.byType(TaskEditor)),
            same(editor),
            reason: 'Keyboard layout must retain the draft/session state',
          );
          expect(state.editingText, same(textSession));
          expect(state.textSaveCommand, same(saveCommand));
          await captureNativeFixtureUi(
            tester,
            'task-editor-$appearance-${withError ? 'picker-error' : 'clean'}-title-ime',
          );
          final scrollable = find
              .ancestor(of: title, matching: find.byType(SingleChildScrollView))
              .first;
          final viewport = tester.getRect(scrollable);
          final lineHeight = editable.renderEditable.preferredLineHeight;
          expect(viewport.height, greaterThanOrEqualTo(lineHeight + 8));
          for (final offset in [0, originalText.length]) {
            controller.selection = TextSelection.collapsed(offset: offset);
            await tester.pumpAndSettle();
            editable.bringIntoView(TextPosition(offset: offset));
            await tester.pumpAndSettle();
            final render = editable.renderEditable;
            final caret = render
                .getLocalRectForCaret(TextPosition(offset: offset))
                .shift(render.localToGlobal(Offset.zero));
            expect(caret.top, greaterThanOrEqualTo(viewport.top - 0.5));
            expect(caret.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
            expect(caret.bottom, lessThanOrEqualTo(360));
          }
          final draft = '$originalText draft';
          controller.value = TextEditingValue(
            text: draft,
            selection: TextSelection.collapsed(offset: draft.length),
            composing: TextRange(
              start: originalText.length + 1,
              end: draft.length,
            ),
          );
          await tester.pumpAndSettle();
          final composingDraft = controller.value;
          tester.view.resetViewInsets();
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          tester.view.padding = const FakeViewPadding(top: 24);
          await tester.pumpAndSettle();
          expect(controller.value, composingDraft);
          expect(state.editingText, same(textSession));
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save changes'),
                )
                .onPressed,
            isNull,
            reason: 'Layout changes must retain the composition guard',
          );
          controller.value = controller.value.copyWith(
            composing: TextRange.empty,
          );
          await tester.pumpAndSettle();
          final committedDraft = controller.value;
          for (final label in ['Delete', 'Cancel', 'Save changes']) {
            final button = label == 'Save changes'
                ? find.widgetWithText(FilledButton, label)
                : find.widgetWithText(TextButton, label);
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            expect(button.hitTestable(), findsOneWidget);
            final rect = tester.getRect(button);
            expect(rect.top, greaterThanOrEqualTo(24));
            expect(rect.bottom, lessThanOrEqualTo(360));
            expect(rect.height, greaterThanOrEqualTo(48));
            final rich = find.descendant(
              of: find.descendant(of: button, matching: find.text(label)),
              matching: find.byType(RichText),
            );
            final paragraph = tester.renderObject<RenderParagraph>(rich);
            expect(paragraph.didExceedMaxLines, false);
          }
          await captureNativeFixtureUi(
            tester,
            'task-editor-$appearance-${withError ? 'picker-error' : 'clean'}-actions-ime',
          );
          if (withError) {
            final notice = find.byKey(const ValueKey('action-error-scroll'));
            expect(notice, findsOneWidget);
            await tester.ensureVisible(notice);
            await tester.pumpAndSettle();
            expect(notice.hitTestable(), findsOneWidget);
            final diagnosticViewport = tester.getRect(notice);
            final diagnosticText = find.descendant(
              of: notice,
              matching: find.text(state.error as String),
            );
            final diagnosticRich = find.descendant(
              of: diagnosticText,
              matching: find.byType(RichText),
            );
            final diagnosticParagraph = tester.renderObject<RenderParagraph>(
              diagnosticRich,
            );
            final diagnosticScroll = tester.state<ScrollableState>(
              find.descendant(of: notice, matching: find.byType(Scrollable)),
            );
            diagnosticScroll.position.jumpTo(
              diagnosticScroll.position.maxScrollExtent,
            );
            await tester.pumpAndSettle();
            final message = state.error as String;
            final ending = message.lastIndexOf('Try again.');
            expect(ending, greaterThanOrEqualTo(0));
            final endingBoxes = diagnosticParagraph.getBoxesForSelection(
              TextSelection(baseOffset: ending, extentOffset: message.length),
            );
            expect(endingBoxes, isNotEmpty);
            for (final box in endingBoxes) {
              final rect = box.toRect().shift(
                diagnosticParagraph.localToGlobal(Offset.zero),
              );
              expect(
                rect.top,
                greaterThanOrEqualTo(diagnosticViewport.top - 0.5),
              );
              expect(
                rect.bottom,
                lessThanOrEqualTo(diagnosticViewport.bottom + 0.5),
              );
            }
            expect(state.error, contains('Could not open the folder picker'));
            await captureNativeFixtureUi(
              tester,
              'task-editor-$appearance-picker-error-readable-ime',
            );
          }
          expect(controller.value, committedDraft);
          expect(identical(state.store, originalStore), true);
          expect(await canonical(), before);
          await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
          expect(find.text('Unsaved changes'), findsOneWidget);
          final guard = find.ancestor(
            of: find.text('Unsaved changes'),
            matching: find.byType(AlertDialog),
          );
          final keepEditing = find.descendant(
            of: guard,
            matching: find.widgetWithText(TextButton, 'Cancel'),
          );
          await tester.ensureVisible(keepEditing);
          await tester.pumpAndSettle();
          await tester.tap(keepEditing);
          await tester.pumpAndSettle();
          expect(controller.value, committedDraft);
          expect(state.editingText, same(textSession));
          await tester.ensureVisible(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(TextButton, 'Discard'));
          await tester.pumpAndSettle();
          expect(find.byType(TaskEditor), findsNothing);
          expect(find.text('Unsaved changes'), findsNothing);
          tester.view.resetViewInsets();
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
          await tester.pumpAndSettle();
          expect(await canonical(), before);
          expect(tester.takeException(), isNull);
        } finally {
          // Flutter verifies this override before registered tearDown callbacks.
          debugDefaultTargetPlatformOverride = null;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );
  }
}

void registerTaskEditorResizeTests() {
  for (final appearance in ['light', 'dark']) {
    testWidgets(
      'Wide selected Tasks editor keeps one diagnostic and composing draft after narrow resize $appearance',
      (tester) async {
        final root = await Directory.systemTemp.createTemp(
          'task-error-resize-',
        );
        final folder = await Directory('${root.path}/shared').create();
        final profile = await Directory('${root.path}/profile').create();
        final seed = await openNativeFixtureStore(
          LocalLogFolder(folder.path),
          '${root.path}/seed',
        );
        final user = const Uuid().v4(), task = const Uuid().v4();
        await seed.command(user, 'user.created', {
          'name': 'Synthetic household',
        });
        await seed.createTasks({task: 'RC68 capture edited'}, user);
        await seed.close();
        await File('${profile.path}/settings.json').writeAsString(
          jsonEncode({
            'folder': folder.path,
            'user': user,
            'appearance': appearance,
          }),
        );
        Map<String, List<int>> canonical() => {
          for (final file in folder.listSync().whereType<File>())
            file.path: file.readAsBytesSync(),
        };
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final picker = _FailingPicker();
        try {
          await tester.pumpWidget(
            TandemlogApp(profilePath: profile.path, folderActions: picker),
          );
          await tester.pumpAndSettle();
          final state = tester.state(find.byType(TasksPage)) as dynamic;
          final before = canonical();
          await flows.openSettings(tester);
          final choose = find.widgetWithText(
            TextButton,
            'Use a different folder',
          );
          await tester.ensureVisible(choose);
          await tester.pumpAndSettle();
          await tester.tap(choose);
          await tester.pumpAndSettle();
          expect(picker.calls, 1);
          await flows.selectTask(tester, task, control: true);
          expect(state.selecting, true);
          expect(state.mobileEditorOpen, false);
          final editor = tester.state<TaskEditorState>(find.byType(TaskEditor));
          final title = find.byKey(const ValueKey('title'));
          final editableFinder = find.descendant(
            of: title,
            matching: find.byType(EditableText),
          );
          final editable = tester.state<EditableTextState>(editableFinder);
          final controller = editable.widget.controller;
          final original = controller.text;
          final draft = '$original resize draft';
          controller.value = TextEditingValue(
            text: draft,
            selection: TextSelection.collapsed(offset: draft.length),
            composing: TextRange(start: original.length + 1, end: draft.length),
          );
          await tester.pumpAndSettle();
          final value = controller.value;
          final textSession = state.editingText;
          final saveCommand = state.textSaveCommand;
          expect(
            find.byKey(const ValueKey('action-error-scroll')),
            findsOneWidget,
          );
          tester.view.physicalSize = const Size(320, 640);
          tester.view.padding = const FakeViewPadding(top: 24);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          // Inspect the first resized frame before later layout can repair a
          // duplicate host/modal diagnostic allocation.
          await tester.pump();
          expect(
            find.byKey(const ValueKey('action-error-scroll')),
            findsOneWidget,
          );
          await tester.pumpAndSettle();
          expect(
            tester.state<TaskEditorState>(find.byType(TaskEditor)),
            same(editor),
          );
          expect(controller.value, value);
          expect(state.editingText, same(textSession));
          expect(state.textSaveCommand, same(saveCommand));
          expect(state.choosingFolder, false);
          expect(state.busy, false);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Save changes'),
                )
                .onPressed,
            isNull,
          );
          await tester.ensureVisible(title);
          await tester.pumpAndSettle();
          await tester.tap(title);
          await tester.pumpAndSettle();
          // Responsive reparenting keeps TaskEditorState and its controller,
          // but may rebuild the nested EditableText. Resolve the live render
          // object after resize instead of measuring the detached wide field.
          final resizedEditable = tester.state<EditableTextState>(
            editableFinder,
          );
          expect(resizedEditable.widget.controller, same(controller));
          resizedEditable.bringIntoView(TextPosition(offset: draft.length));
          await tester.pumpAndSettle();
          final viewport = tester.getRect(
            find
                .ancestor(
                  of: title,
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
          );
          final caret = resizedEditable.renderEditable
              .getLocalRectForCaret(TextPosition(offset: draft.length))
              .shift(resizedEditable.renderEditable.localToGlobal(Offset.zero));
          expect(
            viewport.height,
            greaterThanOrEqualTo(
              resizedEditable.renderEditable.preferredLineHeight + 8,
            ),
          );
          expect(caret.top, greaterThanOrEqualTo(viewport.top - 0.5));
          expect(caret.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
          expect(caret.bottom, lessThanOrEqualTo(360));
          await captureNativeFixtureUi(
            tester,
            'task-editor-$appearance-wide-narrow-title-ime',
          );
          for (final label in ['Delete', 'Cancel', 'Save changes']) {
            final button = label == 'Save changes'
                ? find.widgetWithText(FilledButton, label)
                : find.widgetWithText(TextButton, label);
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            expect(button.hitTestable(), findsOneWidget);
            expect(tester.getRect(button).height, greaterThanOrEqualTo(48));
            expect(tester.getRect(button).bottom, lessThanOrEqualTo(360));
          }
          await captureNativeFixtureUi(
            tester,
            'task-editor-$appearance-wide-narrow-actions-ime',
          );
          expect(canonical(), before);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.view.resetViewPadding();
          tester.view.resetPadding();
          tester.view.resetViewInsets();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerTaskEditorErrorKeyboardTests();
  registerTaskEditorResizeTests();
}
