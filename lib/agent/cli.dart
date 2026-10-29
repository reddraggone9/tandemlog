import 'dart:convert';
import 'dart:io';

import '../platform/host_zone.dart';
import '../domain/wall_time.dart';
import 'agent_profile.dart';
import 'agent_workspace.dart';
import '../storage/profile_lock.dart';
import 'command.dart';
import 'commands_write.dart' show dryRunWrite, observedStateHash;
import 'registry.dart';
import 'render.dart';
import 'windows_zone.dart';

/// Global options precede or follow the command words.
const globalOptions = {'profile', 'wait', 'tz', 'format'};

class CliInvocation {
  CliInvocation(this.command, this.args, this.options, this.format);
  final AgentCommand command;
  final Map<String, Object?> args;
  final AgentOptions options;
  final String format;
}

Future<String> hostZone(Map<String, String> env, String? override) async {
  String zone;
  if (override != null) {
    zone = override;
  } else {
    try {
      if (Platform.isLinux) {
        zone = await readLinuxZone(environment: env);
      } else if (Platform.isWindows) {
        final observed = readWindowsZone();
        zone = observed.id;
        validateLocalOffset(
          zone,
          DateTime.now().toUtc(),
          Duration(seconds: observed.offsetSeconds),
        );
      } else {
        throw StateError('Unsupported platform.');
      }
    } catch (_) {
      throw const AgentFailure(
        'validation',
        'Cannot determine this device\'s time zone; pass --tz <IANA zone>.',
      );
    }
  }
  try {
    timeZoneLocation(zone);
  } catch (_) {
    throw AgentFailure(
      'validation',
      'Unknown time zone "$zone".',
      details: {'field': 'tz', 'error': 'invalid'},
    );
  }
  return zone;
}

/// Runs one command and returns (exit code, stdout text).
Future<(int, String)> runCli(
  List<String> argv, {
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  var format = 'text';
  try {
    final globals = <String, String>{};
    final rest = <String>[];
    for (var i = 0; i < argv.length; i++) {
      final t = argv[i];
      final name = t.startsWith('--') ? t.substring(2).split('=').first : null;
      if (name != null && globalOptions.contains(name)) {
        globals[name] = t.contains('=')
            ? t.substring(t.indexOf('=') + 1)
            : (i + 1 < argv.length
                  ? argv[++i]
                  : throw AgentFailure(
                      'validation',
                      'Missing value for --$name.',
                    ));
      } else {
        rest.add(t);
      }
    }
    format = globals['format'] ?? 'text';
    if (!const {'text', 'json', 'jsonl'}.contains(format)) {
      throw const AgentFailure(
        'validation',
        'Use --format text, json or jsonl.',
      );
    }
    if (rest.isEmpty || rest.first == 'help' || rest.first == '--help') {
      return (0, usage(rest.length > 1 ? rest.sublist(1).join(' ') : null));
    }
    if (rest.first == 'schema') {
      return (
        0,
        const JsonEncoder.withIndent('  ').convert({
          'v': agentOutputVersion,
          'commands': [for (final c in registry) c.schemaJson],
        }),
      );
    }
    final (command, used) = findCommand(rest);
    final tail = rest.sublist(used);
    if (tail.contains('--help')) return (0, command.help);
    final waitSeconds = int.tryParse(globals['wait'] ?? '30');
    if (waitSeconds == null || waitSeconds < 0) {
      throw const AgentFailure(
        'validation',
        '--wait must be a whole number of seconds.',
        details: {'field': 'wait', 'error': 'integer'},
      );
    }
    final wait = Duration(seconds: waitSeconds);
    final options = AgentOptions(
      profile: globals['profile'],
      wait: wait,
      timeZone: command.kind == CommandKind.setup
          ? null
          : await hostZone(env, globals['tz']),
      environment: env,
    );
    final args = command.parse(tail);
    if (format == 'jsonl' && command.paged) args['limit'] = 1 << 30;
    final result = await execute(command, args, options);
    return (result.exitCode, renderResult(result, format, command));
  } catch (e) {
    final failure = AgentWorkspace.translate(e);
    final f = failure is AgentFailure
        ? failure
        : AgentFailure('internal', failure.toString());
    final body = format == 'text'
        ? 'error: ${f.kind}: ${f.message}${f.details == null ? '' : '\n${jsonEncode(f.details)}'}'
        : jsonEncode({'v': agentOutputVersion, 'error': f.toJson()});
    return (f.exitCode, body);
  }
}

(AgentCommand, int) findCommand(List<String> words) {
  for (final n in [2, 1]) {
    if (words.length < n) continue;
    final name = words.take(n).join(' ');
    for (final c in registry) {
      if (c.name == name) return (c, n);
    }
  }
  throw AgentFailure(
    'validation',
    'Unknown command "${words.take(2).join(' ')}". Run `tandemlog-cli help`.',
  );
}

/// Test hook: runs after a planned commit's plan check, before it opens the
/// workspace to append.
Future<void> Function()? debugAfterPlanCheck;

/// Open the right workspace mode, run, close. Shared with the MCP server.
Future<AgentResult> execute(
  AgentCommand command,
  Map<String, Object?> args,
  AgentOptions options,
) async {
  final profile = AgentProfile.resolve(
    selection: options.profile,
    environment: options.environment,
  );
  if (command.kind == CommandKind.setup) {
    return command.run(AgentCall(args, null, options, profile: profile));
  }
  final dryRun = args['dry-run'] == true;
  if (command.kind == CommandKind.write && dryRun) {
    final plan = await dryRunWrite(command, args, options, profile);
    plan.data.remove('inputHash');
    return plan;
  }
  if (command.kind != CommandKind.write || !command.needsPlan(args)) {
    return _run(command, args, options, profile, null);
  }
  final expected = args['expect-plan'] as String?;
  if (expected == null) {
    throw const AgentFailure(
      'validation',
      'This action needs --expect-plan <planHash> from a --dry-run.',
      details: {'field': 'expect-plan', 'error': 'required'},
    );
  }
  // Hold the identity lock from the plan check through the append. The
  // commit runs only while the workspace still has exactly the observed state
  // the plan was computed from; that check repeats inside the append.
  await profile.requireAgentProfile();
  final lock = await profile.lock(options.wait);
  // The real workspace opens while the dry run runs on its profile copy (it
  // starts once the copy exists); the command runs only after the plan check.
  Future<AgentWorkspace>? opening;
  var handedOver = false;
  try {
    final plan = await dryRunWrite(
      command,
      args,
      options,
      profile,
      held: lock,
      afterCopy: () => opening = AgentWorkspace.open(
        profile,
        readOnly: false,
        wait: options.wait,
        held: lock,
      )..ignore(),
    );
    if (plan.data['planHash'] != expected) {
      throw AgentFailure(
        'plan_changed',
        'The plan changed since the dry run; review it again.',
        details: {
          'planHash': plan.data['planHash'],
          'effects': plan.data['effects'],
        },
      );
    }
    final input = plan.data['inputHash'] as String;
    await debugAfterPlanCheck?.call();
    handedOver = true;
    return await _run(
      command,
      args,
      options,
      profile,
      lock,
      planInput: input,
      opened: opening,
    );
  } finally {
    if (!handedOver && opening != null) {
      try {
        await (await opening!).close();
      } catch (_) {
        // The refusal or failure already being reported takes precedence.
      }
    }
    await lock.close();
  }
}

Future<AgentResult> _run(
  AgentCommand command,
  Map<String, Object?> args,
  AgentOptions options,
  AgentProfile profile,
  ProfileLock? held, {
  String? planInput,
  Future<AgentWorkspace>? opened,
}) async {
  final ws =
      await opened ??
      await AgentWorkspace.open(
        profile,
        readOnly: command.kind == CommandKind.read,
        wait: options.wait,
        held: held,
      );
  late final AgentCall call;
  bool planHolds() => observedStateHash(call) == planInput;
  call = AgentCall(
    args,
    ws,
    options,
    planGuard: planInput == null ? null : planHolds,
  );
  try {
    if (planInput != null && !planHolds()) {
      throw const AgentFailure(
        'plan_changed',
        'The workspace changed after the plan check; run the dry run again.',
      );
    }
    return await command.run(call);
  } catch (e) {
    final failure = AgentWorkspace.translate(e);
    // A planned commit's in-append guard refused because the workspace moved
    // on since the plan: report it as such (re-plan), not as a stale rev.
    if (planInput != null &&
        failure is AgentFailure &&
        failure.kind == 'stale' &&
        !planHolds()) {
      throw const AgentFailure(
        'plan_changed',
        'The workspace changed after the plan check; run the dry run again.',
      );
    }
    throw failure;
  } finally {
    await ws.close();
  }
}

String renderResult(AgentResult result, String format, AgentCommand command) {
  switch (format) {
    case 'json':
      return capJson({
        'v': agentOutputVersion,
        ...result.data,
      }, nextAfter: result.nextAfter);
    case 'jsonl':
      final list = result.data.values.whereType<List>().firstOrNull;
      if (list == null) {
        return jsonEncode({'v': agentOutputVersion, ...result.data});
      }
      return list.map(jsonEncode).join('\n');
    default:
      return result.text;
  }
}

/// The 32 KB (UTF-8) cap applies to JSON and MCP output too: trailing rows
/// of the main list are dropped, `truncated`/`shown` say so and `next`
/// resumes at the first dropped row; `--format jsonl` streams everything.
String capJson(
  Map<String, Object?> data, {
  String? Function(int shown)? nextAfter,
}) {
  var encoded = jsonEncode(data);
  int size(String s) => utf8.encode(s).length;
  if (size(encoded) <= outputCapBytes) return encoded;
  final key = data.entries.where((e) => e.value is List).firstOrNull?.key;
  if (key == null) return encoded;
  final all = data[key] as List;
  String withRows(int n) => jsonEncode({
    ...data,
    key: all.sublist(0, n),
    'truncated': true,
    'shown': n,
    if (nextAfter != null || data.containsKey('next'))
      'next': nextAfter?.call(n),
  });
  // Largest row count that fits (binary search; output size grows with n).
  var lo = 0, hi = all.length;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (size(withRows(mid)) <= outputCapBytes) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return withRows(lo);
}

String usage(String? topic) {
  if (topic != null) {
    final matches = registry.where((c) => c.name.startsWith(topic));
    if (matches.isNotEmpty) return matches.map((c) => c.help).join('\n');
  }
  final b = StringBuffer()
    ..writeln('tandemlog-cli — read and change TandemLog data.')
    ..writeln()
    ..writeln(
      'Global: --profile <name|path> (or TANDEMLOG_CLI_PROFILE), --format text|json|jsonl, --tz <zone>, --wait <seconds>',
    )
    ..writeln()
    ..writeln('Commands:');
  for (final c in registry) {
    b.writeln('  ${c.name.padRight(18)} ${c.summary}');
  }
  b
    ..writeln('  ${'schema'.padRight(18)} Machine-readable command list.')
    ..writeln(
      '  ${'mcp'.padRight(18)} Serve these commands as MCP tools over stdio.',
    );
  return b.toString().trimRight();
}
