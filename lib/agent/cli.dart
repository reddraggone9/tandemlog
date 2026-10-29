import 'dart:convert';
import 'dart:io';

import '../platform/host_zone.dart';
import '../domain/wall_time.dart';
import 'agent_profile.dart';
import 'agent_workspace.dart';
import '../storage/profile_lock.dart';
import 'command.dart';
import 'commands_write.dart' show dryRunWrite;
import 'registry.dart';
import 'render.dart';

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
  final zone =
      override ??
      (Platform.isLinux
          ? await readLinuxZone(environment: env)
          : (env['TZ']?.isNotEmpty ?? false)
          ? env['TZ']!
          : throw const AgentFailure(
              'validation',
              'Cannot determine the time zone; pass --tz <IANA zone>.',
            ));
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
    final wait = Duration(seconds: int.tryParse(globals['wait'] ?? '') ?? 30);
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
    return (0, renderResult(result, format, command));
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
  if (command.kind == CommandKind.write && dryRun && !command.ownDryRun) {
    return dryRunWrite(command, args, options, profile);
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
  // Hold the identity lock from the plan check through the append.
  await profile.requireAgentProfile();
  final lock = await profile.lock(options.wait);
  try {
    final plan = await dryRunWrite(command, args, options, profile, held: lock);
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
    return await _run(command, args, options, profile, lock);
  } finally {
    await lock.close();
  }
}

Future<AgentResult> _run(
  AgentCommand command,
  Map<String, Object?> args,
  AgentOptions options,
  AgentProfile profile,
  ProfileLock? held,
) async {
  final ws = await AgentWorkspace.open(
    profile,
    readOnly: command.kind == CommandKind.read,
    wait: options.wait,
    held: held,
  );
  try {
    return await command.run(AgentCall(args, ws, options));
  } catch (e) {
    throw AgentWorkspace.translate(e);
  } finally {
    await ws.close();
  }
}

String renderResult(AgentResult result, String format, AgentCommand command) {
  switch (format) {
    case 'json':
      return jsonEncode({'v': agentOutputVersion, ...result.data});
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
