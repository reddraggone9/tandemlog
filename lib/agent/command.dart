import 'agent_profile.dart';
import 'agent_workspace.dart';

/// One argument of a registry command. The same declaration produces argv
/// parsing, `--help`, `tandemlog-cli schema` and MCP `inputSchema`.
class AgentArg {
  const AgentArg(
    this.name,
    this.type,
    this.description, {
    this.required = false,
    this.positional = false,
    this.choices,
    this.repeated = false,
  });
  final String name, type, description;
  final bool required, positional, repeated;
  final List<String>? choices;

  Map<String, Object?> get jsonSchema {
    final item = <String, Object?>{
      'type': type,
      if (choices != null) 'enum': choices,
    };
    return repeated
        ? {'type': 'array', 'items': item, 'description': description}
        : {...item, 'description': description};
  }
}

enum CommandKind { read, write, setup }

class AgentResult {
  AgentResult(
    this.data,
    String text, {
    this.nextAfter,
    this.nextWithinFirst,
    this.membersField,
    this.exitCode = 0,
  }) : _text = (() => text);

  /// Builds the text form only if a caller asks for it: a `--format json`
  /// call never renders it.
  AgentResult.lazy(
    this.data,
    String Function() text, {
    this.nextAfter,
    this.nextWithinFirst,
    this.membersField,
    this.exitCode = 0,
  }) : _text = text;
  final Map<String, Object?> data;
  final String Function() _text;
  late final String text = _text();

  /// For paged results: the cursor resuming after the first [shown] rows of
  /// this page, so a truncated output still pages without skipping rows.
  final String? Function(int shown)? nextAfter;

  /// For paged results whose first row has a member list (a Food row's
  /// containers): the cursor resuming inside that row after [members] more
  /// of its members, used when that one row alone exceeds the output cap.
  final String Function(int members)? nextWithinFirst;

  /// The first row's member list [nextWithinFirst] pages (`containers`).
  final String? membersField;

  /// Non-zero for a result that is also a failure (a partial bulk edit).
  final int exitCode;
}

/// Arguments after parsing, plus the open workspace for read/write commands.
class AgentCall {
  AgentCall(
    this.args,
    this.workspace,
    this.options, {
    this.profile,
    this.planGuard,
  });
  final Map<String, Object?> args;
  final AgentWorkspace? workspace;
  final AgentOptions options;
  final AgentProfile? profile;

  /// For a planned commit: true while the workspace still has exactly the
  /// state the dry run planned against. Every store `canCommit` of a planned
  /// command includes it, so the check runs inside the serialized append.
  final bool Function()? planGuard;

  /// [guard] plus the plan check, for a store's `canCommit`.
  bool Function() commitGuard(bool Function() guard) {
    final plan = planGuard;
    return plan == null ? guard : () => guard() && plan();
  }

  AgentWorkspace get ws => workspace!;
  String? string(String name) => args[name] as String?;
  int? integer(String name) => args[name] as int?;
  bool flag(String name) => args[name] == true;
  List<String> strings(String name) =>
      (args[name] as List?)?.cast<String>() ?? const [];
  String require(String name) =>
      string(name) ??
      (throw AgentFailure(
        'validation',
        'Missing --$name.',
        details: {'field': name, 'error': 'required'},
      ));
}

class AgentOptions {
  AgentOptions({
    this.profile,
    this.wait = const Duration(seconds: 30),
    this.timeZone,
    this.environment,
    this.purchasePlanBytes,
  });
  final String? profile;
  final Duration wait;
  final String? timeZone;
  final Map<String, String>? environment;

  /// Exact plan-file input frozen once per execute, shared by preview and commit.
  final List<int>? purchasePlanBytes;
}

class AgentCommand {
  const AgentCommand(
    this.name,
    this.summary,
    this.kind,
    this.args,
    this.run, {
    this.paged = false,
    this.requiresPlan = false,
    this.planWhen,
    this.destructive = false,
    this.planCheckedInAppend = false,
  });
  final String name, summary;
  final CommandKind kind;
  final List<AgentArg> args;
  final Future<AgentResult> Function(AgentCall call) run;
  final bool paged;

  /// Bulk actions, merges and imports commit only with the planHash of a dry
  /// run (`--expect-plan`); [planWhen] narrows that to some argument shapes.
  final bool requiresPlan;
  final bool Function(Map<String, Object?> args)? planWhen;

  /// Deletes, removes or merges (MCP `destructiveHint`).
  final bool destructive;

  /// Its one append checks [AgentCall.commitGuard] (so the plan) inside the
  /// append before reserving anything (crash-tail cleanup of the own log may
  /// precede a refusal, as for any append); a planned commit then skips the
  /// redundant plan check before the command, which would see the same or an
  /// older state. Set only where a test proves the in-append refusal.
  final bool planCheckedInAppend;

  bool needsPlan(Map<String, Object?> args) =>
      requiresPlan && (planWhen?.call(args) ?? true);

  String get toolName => name.replaceAll(' ', '_');

  List<AgentArg> get allArgs => [
    ...args,
    if (paged) ...pagingArgs,
    if (kind == CommandKind.write) ...writeArgs,
    if (requiresPlan) planArg,
  ];

  static const planArg = AgentArg(
    'expect-plan',
    'string',
    'planHash from the dry run; required to commit bulk actions, merges and imports.',
  );

  static const pagingArgs = [
    AgentArg('limit', 'integer', 'Maximum rows (default 50).'),
    AgentArg('cursor', 'string', 'Opaque cursor from a previous `next`.'),
  ];
  static const writeArgs = [
    AgentArg(
      'dry-run',
      'boolean',
      'Report the exact effects and planHash without appending.',
    ),
  ];

  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {for (final a in allArgs) a.name: a.jsonSchema},
    'required': [
      for (final a in allArgs)
        if (a.required) a.name,
    ],
    'additionalProperties': false,
  };

  Map<String, Object?> get schemaJson => {
    'name': name,
    'tool': toolName,
    'summary': summary,
    'kind': kind.name,
    'inputSchema': inputSchema,
  };

  /// Parse argv after the command words. `--name value`, `--name=value`,
  /// boolean `--flag`, repeated flags for arrays, positionals in order.
  Map<String, Object?> parse(List<String> argv) {
    final out = <String, Object?>{};
    final byName = {for (final a in allArgs) a.name: a};
    final positionals = allArgs.where((a) => a.positional).toList();
    var position = 0;
    for (var i = 0; i < argv.length; i++) {
      final token = argv[i];
      if (token.startsWith('--') && token.length > 2) {
        var name = token.substring(2);
        String? value;
        final eq = name.indexOf('=');
        if (eq >= 0) {
          value = name.substring(eq + 1);
          name = name.substring(0, eq);
        }
        final arg = byName[name];
        if (arg == null) {
          throw AgentFailure('validation', 'Unknown option --$name for $name.');
        }
        if (arg.type == 'boolean' && !arg.repeated) {
          out[name] = value == null ? true : value == 'true';
          continue;
        }
        if (value == null) {
          if (i + 1 >= argv.length) {
            throw AgentFailure('validation', 'Missing value for --$name.');
          }
          value = argv[++i];
        }
        _store(out, arg, value);
      } else {
        if (position >= positionals.length) {
          throw AgentFailure('validation', 'Unexpected argument "$token".');
        }
        _store(out, positionals[position], token);
        if (!positionals[position].repeated) position++;
      }
    }
    return validate(out);
  }

  void _store(Map<String, Object?> out, AgentArg arg, String raw) {
    final Object value = switch (arg.type) {
      'integer' =>
        int.tryParse(raw) ??
            (throw AgentFailure(
              'validation',
              '--${arg.name} must be a whole number.',
              details: {'field': arg.name, 'error': 'integer'},
            )),
      'boolean' => raw == 'true',
      _ => raw,
    };
    if (arg.repeated) {
      ((out[arg.name] ??= <Object>[]) as List).add(value);
    } else {
      out[arg.name] = value;
    }
  }

  /// MCP arguments arrive as JSON; both paths share this validation.
  Map<String, Object?> validate(Map<String, Object?> input) {
    final byName = {for (final a in allArgs) a.name: a};
    for (final key in input.keys) {
      if (!byName.containsKey(key)) {
        throw AgentFailure('validation', 'Unknown argument "$key".');
      }
    }
    for (final a in allArgs) {
      final v = input[a.name];
      if (v == null) {
        if (a.required) {
          throw AgentFailure(
            'validation',
            'Missing ${a.name}.',
            details: {'field': a.name, 'error': 'required'},
          );
        }
        continue;
      }
      bool ok(Object? x) => switch (a.type) {
        'integer' => x is int,
        'boolean' => x is bool,
        _ => x is String && (a.choices == null || a.choices!.contains(x)),
      };
      if (a.repeated ? !(v is List && v.every(ok)) : !ok(v)) {
        throw AgentFailure(
          'validation',
          'Invalid ${a.name}${a.choices == null ? '' : ' (one of ${a.choices!.join(', ')})'}.',
          details: {'field': a.name, 'error': 'invalid'},
        );
      }
    }
    return input;
  }

  String get help {
    final b = StringBuffer('tandemlog-cli $name');
    for (final a in allArgs.where((a) => a.positional)) {
      b.write(a.required ? ' <${a.name}>' : ' [${a.name}]');
    }
    b
      ..writeln()
      ..writeln('  $summary');
    for (final a in allArgs) {
      final flag = a.positional ? a.name : '--${a.name}';
      b.writeln(
        '  $flag${a.required ? ' (required)' : ''}: ${a.description}'
        '${a.choices == null ? '' : ' [${a.choices!.join('|')}]'}'
        '${a.repeated ? ' (repeatable)' : ''}',
      );
    }
    return b.toString();
  }
}
