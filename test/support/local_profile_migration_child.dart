import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:tandemlog/storage/local_profile_database.dart';
import 'package:tandemlog/storage/local_profile_migration.dart';
import 'package:tandemlog/storage/task_store.dart';
import 'package:tandemlog/storage/log_folder.dart';

Future<void> main(List<String> args) async {
  if (args[1] == 'legacy-wal') {
    const writer = '00000000-0000-4000-8000-000000000001',
        user = '00000000-0000-4000-8000-000000000002',
        task = '00000000-0000-4000-8000-000000000003';
    final shared = '${args[0]}/canonical', private = '${args[0]}/profile';
    final key = sha256.convert(utf8.encode(shared)).toString();
    final store = await TaskStore.open(
      LocalLogFolder(shared),
      '$private/spaces/$key',
      writerIdentity: writer,
      writerGuard: FileWriterGuard(private),
    );
    await store.command(user, 'user.created', {'name': 'Synthetic'});
    await store.command(task, 'task.created', {
      'title': 'Committed hot WAL',
      'description': '',
      'assignee': user,
    });
    Timer.periodic(
      const Duration(seconds: 1),
      (_) => store.db.select('SELECT 1'),
    );
    stdout.writeln('ready');
    await stdout.flush();
    await Completer<void>().future;
    return;
  }
  final profile = await LocalProfileDatabase.open(args[0]);
  await LocalProfileMigration(profile).run(
    checkpoint: (boundary, path) async {
      if (boundary == args[1]) {
        Timer.periodic(
          const Duration(seconds: 1),
          (_) => profile.database.select('SELECT 1'),
        );
        stdout.writeln('ready');
        await stdout.flush();
        await Completer<void>().future;
      }
    },
  );
  await profile.close();
}
