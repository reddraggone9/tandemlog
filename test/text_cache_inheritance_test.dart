import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import 'package:tandemlog/domain/event.dart';
import 'package:tandemlog/domain/text_actor.dart';
import 'package:tandemlog/domain/text_context.dart';
import 'package:tandemlog/storage/text_cache.dart';
import 'package:tandemlog/text/native_text_engine.dart';
import 'package:tandemlog/text/recurring_text.dart';

void main() {
  test(
    'resolved inherited cache preserves original claims and rebuilds corrupt disposable state',
    () {
      final engine = NativeTextEngine(
        libraryPath: Platform.environment['TANDEMLOG_TEXT_LIBRARY'],
      );
      final db = sqlite3.openInMemory();
      db.execute(
        'CREATE TABLE text_fields(entity TEXT,field TEXT,context TEXT,codec TEXT,adapter INTEGER,seed_hash TEXT,state BLOB,state_hash TEXT,frontier TEXT,PRIMARY KEY(entity,field))',
      );
      db.execute(
        'CREATE TABLE text_actors(context TEXT,actor INTEGER,writer TEXT,allocation TEXT,PRIMARY KEY(context,actor))',
      );
      const space = '00000000-0000-4000-8000-000000000001',
          parent = '00000000-0000-4000-8000-000000000002',
          writer = '00000000-0000-4000-8000-000000000003';
      final child = const Uuid().v5(parent, 'successor');
      try {
        final fields = <String, ResolvedTextField>{};
        String? originalContext;
        for (final name in ['title', 'description']) {
          final seed = engine.seedText('AB');
          final context = TextFieldContext(
            space: space,
            entity: parent,
            field: name,
            basis: '$writer:1',
            basisKind: 'native-creation',
            seedHash: sha256.convert(seed.bytes).toString(),
          );
          final childContext = TextFieldContext.successor(context, child);
          final document = engine.createDocument(
            actorClientId: 2,
            limits: const NativeTextLimits(visibleUtf16: 500),
            seed: seed,
          );
          final operations = <LineageTextOperation>[];
          try {
            if (name == 'title') {
              originalContext = context.hash;
              final allocation = const Uuid().v4(),
                  actor = deriveTextActor(context.hash, writer, allocation);
              final draft = document.captureDraft(actorClientId: actor)
                ..replaceText('AXB');
              final saved = draft.prepareSave(), update = saved.update;
              final event = LogEvent.decode(
                LogEvent(
                  space,
                  writer,
                  1,
                  EventClock(BigInt.one),
                  parent,
                  'task.textEdited',
                  {
                    'changes': {
                      'title': {
                        'context': context.hash,
                        'allocation': allocation,
                        'actor': actor,
                        'update': update.encoded,
                      },
                    },
                  },
                ).encode(),
              );
              saved.cancel();
              document.applyRemote(update);
              operations.add(
                LineageTextOperation(
                  event,
                  name,
                  TextActorClaim(
                    context: context.hash,
                    writer: writer,
                    allocation: allocation,
                    actor: actor,
                  ),
                  update,
                ),
              );
            }
            fields[name] = ResolvedTextField(
              context: childContext,
              seed: seed,
              operations: operations,
              state: document.fullState,
              text: document.read().text,
            );
          } finally {
            document.dispose();
          }
        }
        final cache = TextCache(db, engine),
            view = <String, dynamic>{'id': child};
        cache.materializeResolved(view, fields);
        expect(view['title'], 'AXB');
        expect(view['description'], 'AB');
        final actor = db.select('SELECT * FROM text_actors').single;
        expect(actor['context'], originalContext);
        expect(actor['context'], isNot(fields['title']!.context.hash));
        expect(
          jsonDecode(
            db
                    .select(
                      "SELECT frontier FROM text_fields WHERE field='title'",
                    )
                    .single['frontier']
                as String,
          ),
          ['$writer:1'],
        );
        db.execute(
          "UPDATE text_fields SET state=x'0000',state_hash='bad',frontier='[]'",
        );
        cache.materializeResolved(view, fields);
        expect(view['title'], 'AXB');
        expect(
          db
              .select("SELECT state_hash FROM text_fields WHERE field='title'")
              .single['state_hash'],
          fields['title']!.stateHash,
        );
        final bad = Map<String, ResolvedTextField>.from(fields);
        final original = fields['title']!;
        bad['title'] = ResolvedTextField(
          context: original.context,
          seed: original.seed,
          operations: original.operations,
          state: original.state,
          text: 'forged',
        );
        expect(
          () => cache.materializeResolved(view, bad),
          throwsA(isA<FormatFailure>()),
        );
        expect(view['title'], 'AXB');
      } finally {
        engine.dispose();
        db.close();
      }
    },
    skip: Platform.environment['TANDEMLOG_TEXT_LIBRARY'] == null
        ? 'Actual native library required'
        : false,
  );
}
