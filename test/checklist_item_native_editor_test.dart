import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/application/task_text_session.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/presentation/checklist_item_editor.dart';

void main() {
  testWidgets('native caret-only edits stay clean; composition propagates; committed merged text renews before close', (tester) async {
    final engine=NativeTextEngine(libraryPath:Platform.environment['TANDEMLOG_TEXT_LIBRARY']);
    addTearDown(engine.dispose);
    const id='00000000-0000-4000-8000-000000000001';
    final fields=<String,TaskTextFieldCapture>{};
    for(final field in ['title','description']) {
      final actor=field=='title'?101:201;
      fields[field]=TaskTextFieldCapture(field:field,context:(field=='title'?'a':'b')*64,allocation:id,actor:actor+1,undoActor:actor,undoAllocation:id,document:engine.createDocument(actorClientId:actor,limits:NativeTextLimits(visibleUtf16:field=='title'?500:10000),seed:engine.seedText(field=='title'?'Base':'Notes')));
    }
    final session=TaskTextSession(TaskTextCapture(id,fields,writer:id));
    addTearDown(session.cancel);
    final key=GlobalKey<ChecklistItemEditorState>();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:ChecklistItemEditor(key:key,item:{'id':id,'title':'Base','description':'Notes'},textSession:session,onClose:(){},save:(_,_) async {
      final remote=fields['title']!.document.captureDraft(actorClientId:103)..replaceText('Remote Base');
      final packet=remote.prepareSave();
      packet.commit(receiptUpdate:packet.update);
      final prepared=session.prepare();
      final event=LogEvent(id,id,1,EventClock(BigInt.one),id,'task.textEdited',{'changes':prepared.changes});
      final receipt=OperationReceipt(id,event.encode(),id);
      prepared.bindReceipt(receipt);
      prepared.commitReceipt(receipt);
    }))));
    await tester.pumpAndSettle();
    final title=tester.widget<TextField>(find.byKey(const Key('checklist-item-title'))).controller!;
    title.selection=const TextSelection.collapsed(offset:1);
    await tester.pump();
    expect(session.hasTextChanges,isFalse);
    expect(await key.currentState!.canClose(),isTrue);
    title.value=const TextEditingValue(text:'Base local',selection:TextSelection.collapsed(offset:10),composing:TextRange(start:5,end:10));
    await tester.pump();
    expect(session.prepare,throwsStateError);
    title.value=title.value.copyWith(composing:TextRange.empty);
    await tester.pump();
    final close=key.currentState!.canClose();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton,'Save'));
    await tester.pumpAndSettle();
    expect(await close,isTrue);
    expect(title.text,'Remote Base local');
    expect(title.text,session.text('title'));
    expect(session.hasTextChanges,isFalse);
    expect(await key.currentState!.canClose(),isTrue);
    expect(fields['title']!.document.isClosed,isFalse);
  });
}
