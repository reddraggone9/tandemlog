import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/storage/profile_lock.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tandemlog-profile-lock');
  });
  tearDown(() => root.delete(recursive: true));

  test('same process and canonical aliases contend until release', () async {
    final profile = '${root.path}/profile';
    final first = await ProfileLock.acquire(profile);
    final alias = Link('${root.path}/alias');
    if (!Platform.isWindows) await alias.create(profile);
    try {
      await expectLater(
        ProfileLock.acquire(profile),
        throwsA(isA<ProfileInUse>()),
      );
      if (!Platform.isWindows) {
        await expectLater(
          ProfileLock.acquire(alias.path),
          throwsA(isA<ProfileInUse>()),
        );
      }
    } finally {
      await first.close();
      await first.close();
    }
    final second = await ProfileLock.acquire(profile);
    await second.close();
  });

  test('failed acquisition releases the process guard for retry', () async {
    final obstructed = await Directory(
      '${root.path}/profile/profile.lock',
    ).create(recursive: true);
    await expectLater(
      ProfileLock.acquire('${root.path}/profile'),
      throwsA(isA<FileSystemException>()),
    );
    await obstructed.delete();
    final lock = await ProfileLock.acquire('${root.path}/profile');
    await lock.close();
  });

  test('child process holds OS lock; killing it allows reacquisition', () async {
    final source = File('${root.path}/child.dart');
    final library = File('lib/storage/profile_lock.dart').absolute.uri;
    await source.writeAsString('''
import 'dart:io';
import '$library';
Future<void> main(List<String> args) async {
  final lock = await ProfileLock.acquire(args.single);
  stdout.writeln('locked');
  await stdin.drain<void>();
  await lock.close();
}
''');
    final executable = Platform.resolvedExecutable;
    final cache = executable.indexOf(
      '${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}',
    );
    final dart = cache < 0
        ? executable
        : '${executable.substring(0, cache)}/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
    final child = await Process.start(dart, [
      source.path,
      '${root.path}/profile',
    ]);
    final stderr = child.stderr.transform(utf8.decoder).join();
    try {
      expect(
        await child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 15)),
        'locked',
      );
      await expectLater(
        ProfileLock.acquire(
          '${root.path}/profile',
        ).timeout(const Duration(seconds: 3)),
        throwsA(isA<ProfileInUse>()),
      );
    } finally {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode.timeout(const Duration(seconds: 15));
    }
    expect(await stderr, isEmpty);
    final lock = await ProfileLock.acquire('${root.path}/profile');
    await lock.close();
  });
}
