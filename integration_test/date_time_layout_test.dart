import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/date_time_layout_test.dart' as checks;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final directory = Platform.environment['DATE_LAYOUT_EVIDENCE'];
  Process? recording;
  checks.registerDateTimeLayoutTests(
    capture: directory == null
        ? null
        : (tester, name) async {
            await Directory(directory).create(recursive: true);
            if (recording == null &&
                Platform.environment['DATE_LAYOUT_RECORD'] == '1') {
              recording = await Process.start('ffmpeg', [
                '-y',
                '-loglevel',
                'error',
                '-f',
                'x11grab',
                '-draw_mouse',
                '1',
                '-framerate',
                '10',
                '-video_size',
                '1000x1000',
                '-i',
                Platform.environment['DISPLAY']!,
                '-c:v',
                'libx264',
                '-preset',
                'veryfast',
                '-crf',
                '23',
                '-pix_fmt',
                'yuv420p',
                '$directory/native-linux.mp4',
              ]);
              final errors = recording!.stderr.drain<void>();
              final output = recording!.stdout.drain<void>();
              addTearDown(() async {
                recording!.stdin.write('q\n');
                expect(await recording!.exitCode, 0);
                await errors;
                await output;
              });
            }
            final result = await Process.run('xdotool', [
              'search',
              '--onlyvisible',
              '--name',
              r'^tandemlog$',
            ]);
            expect(result.exitCode, 0);
            final window = result.stdout.toString().trim().split('\n').last;
            final size = tester.getSize(find.byType(Scaffold));
            await Process.run('xdotool', [
              'windowsize',
              window,
              size.width.round().toString(),
              size.height.round().toString(),
            ]);
            await Process.run('xdotool', ['windowmove', window, '0', '0']);
            final time = tester.getCenter(
              find.byKey(const ValueKey('dueTime')),
            );
            await Process.run('xdotool', [
              'mousemove',
              time.dx.round().toString(),
              time.dy.round().toString(),
            ]);
            await Future<void>.delayed(const Duration(milliseconds: 700));
            expect(
              (await Process.run('import', [
                '-window',
                window,
                '$directory/$name.png',
              ])).exitCode,
              0,
            );
          },
  );
}
