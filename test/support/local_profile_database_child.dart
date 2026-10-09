import 'dart:io';
import 'package:tandemlog/storage/local_profile_database.dart';

Future<void> main(List<String> args) async {
  final profile = await LocalProfileDatabase.open(args[0]);
  final db = profile.database;
  db.execute('CREATE TABLE evidence (value TEXT NOT NULL)');
  db.execute("INSERT INTO evidence VALUES ('durable')");
  db.execute('BEGIN IMMEDIATE');
  db.execute("INSERT INTO evidence VALUES ('committed')");
  if (args[1] != 'uncommitted') {
    db.execute(args[1] == 'commit' ? 'COMMIT' : 'ROLLBACK');
  }
  stdout.writeln('ready');
  await stdin.drain<void>();
  await profile.close();
}
