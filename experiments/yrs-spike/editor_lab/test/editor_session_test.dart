// Frozen before harness implementation. Actual native bridge, synthetic data.
import 'package:flutter_test/flutter_test.dart';
import 'package:yrs_editor_lab/editor_session.dart';

void main() {
  late EditorSession session;
  setUp(() => session = EditorSession());
  tearDown(() => session.dispose());

  test('H01 native library initializes two Unicode replicas', () {
    expect(session.committedA, 'A😀B');
    expect(session.committedB, 'A😀B');
  });
  test('H02 typing modifies private captured draft until Save', () {
    session.beginEdit();
    session.replaceDraft('A😀日本B');
    expect(session.draftText, 'A😀日本B');
    expect(session.committedA, 'A😀B');
    expect(session.publishedLocalUpdates, 0);
  });
  test('H03 Save merges captured changes after remote prefix', () {
    session.beginEdit();
    session.replaceDraft('A😀日本B');
    session.remotePrefix();
    expect(session.draftText, 'A😀日本B');
    session.save();
    expect(session.committedA, 'REMOTE A😀日本B');
    expect(session.committedB, session.committedA);
    expect(session.publishedLocalUpdates, 1);
    expect(session.editing, false);
  });
  test('H04 composing guard rejects Save without mutation', () {
    session.beginEdit();
    session.replaceDraft('A😀にB');
    session.setComposing(true);
    expect(session.save, throwsStateError);
    expect(session.committedA, 'A😀B');
    expect(session.draftText, 'A😀にB');
    expect(session.publishedLocalUpdates, 0);
    expect(session.editing, true);
  });
  test('H05 composition commit saves once', () {
    session.beginEdit();
    session.setComposing(true);
    session.replaceDraft('A😀にB');
    session.replaceDraft('A😀日本B');
    session.setComposing(false);
    session.save();
    expect(session.save, throwsStateError);
    expect(session.publishedLocalUpdates, 1);
    expect(session.committedA, 'A😀日本B');
  });
  test('H06 Cancel retains arriving remote work and publishes none', () {
    session.beginEdit();
    session.replaceDraft('DISCARD A😀B');
    session.remotePrefix();
    session.cancel();
    expect(session.committedA, 'REMOTE A😀B');
    expect(session.committedB, session.committedA);
    expect(session.publishedLocalUpdates, 0);
  });
  test('H08 selective Undo/Redo retain remote prefix', () {
    session.beginEdit();
    session.replaceDraft('A😀日本B');
    session.remotePrefix();
    session.save();
    session.undo();
    expect(session.committedA, 'REMOTE A😀B');
    expect(session.committedB, session.committedA);
    session.redo();
    expect(session.committedA, 'REMOTE A😀日本B');
    expect(session.committedB, session.committedA);
  });
  test('H09 emoji replacements never split UTF16 pairs', () {
    session.beginEdit();
    session.replaceDraft('A😁B');
    session.replaceDraft('A👩‍💻B');
    session.save();
    expect(session.committedA, 'A👩‍💻B');
    expect(session.committedB, session.committedA);
  });
}
