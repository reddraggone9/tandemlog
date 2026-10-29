import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'agent_profile.dart';
import 'agent_workspace.dart';
import 'cli.dart';
import 'command.dart';
import 'registry.dart';
import 'render.dart';

/// MCP over stdio (newline-delimited JSON-RPC 2.0). Each tool call opens the
/// workspace, runs one registry command and closes it, so no work runs while
/// idle and every call admits peer writes first.
class McpServer {
  McpServer({this.environment, this.profile, this.timeZone});
  final Map<String, String>? environment;
  final String? profile, timeZone;
  static const protocolVersion = '2025-06-18';

  Future<void> serve(Stream<List<int>> input, IOSink output) async {
    var queue = Future<void>.value();
    await for (final line
        in input.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      // Calls run one at a time; the profile lock would serialize them anyway.
      queue = queue.then((_) async {
        final reply = await handle(line);
        if (reply != null) output.writeln(jsonEncode(reply));
        await output.flush();
      });
    }
    await queue;
  }

  Future<Map<String, Object?>?> handle(String line) async {
    Object? id;
    try {
      final message = jsonDecode(line) as Map<String, Object?>;
      id = message['id'];
      final method = message['method'] as String?;
      final params = (message['params'] as Map?)?.cast<String, Object?>() ?? {};
      if (id == null) return null; // notification
      final result = switch (method) {
        'initialize' => {
          'protocolVersion': protocolVersion,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {
            'name': 'tandemlog-cli',
            'version': '$agentOutputVersion',
          },
          'instructions':
              'TandemLog tasks and Food. Call context first. Writes to existing items need the rev from list/show; bulk actions, merges and imports need planHash from a dry run.',
        },
        'ping' => <String, Object?>{},
        'tools/list' => {
          'tools': [
            for (final c in registry.where((c) => c.kind != CommandKind.setup))
              {
                'name': c.toolName,
                'description': c.summary,
                'inputSchema': c.inputSchema,
                'annotations': {
                  'readOnlyHint': c.kind == CommandKind.read,
                  'destructiveHint': false,
                  'idempotentHint': c.kind == CommandKind.read,
                },
              },
          ],
        },
        'tools/call' => await _call(params),
        _ => throw _RpcError(-32601, 'Unknown method $method'),
      };
      return {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on _RpcError catch (e) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': e.code, 'message': e.message},
      };
    } on FormatException catch (e) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32700, 'message': e.message},
      };
    }
  }

  Future<Map<String, Object?>> _call(Map<String, Object?> params) async {
    final name = params['name'];
    final command = registry
        .where((c) => c.toolName == name && c.kind != CommandKind.setup)
        .firstOrNull;
    if (command == null) throw _RpcError(-32602, 'Unknown tool $name');
    try {
      final args = command.validate(
        Map<String, Object?>.from((params['arguments'] as Map?) ?? {}),
      );
      final env = environment ?? Platform.environment;
      final options = AgentOptions(
        profile: profile,
        timeZone: await hostZone(env, timeZone),
        environment: env,
      );
      final result = await execute(command, args, options);
      return {
        'content': [
          {'type': 'text', 'text': result.text},
        ],
        'structuredContent': {'v': agentOutputVersion, ...result.data},
        'isError': false,
      };
    } catch (e) {
      final f = AgentWorkspace.translate(e);
      final failure = f is AgentFailure ? f : AgentFailure('error', '$f');
      return {
        'content': [
          {
            'type': 'text',
            'text': 'error: ${failure.kind}: ${failure.message}',
          },
        ],
        'structuredContent': {
          'v': agentOutputVersion,
          'error': failure.toJson(),
        },
        'isError': true,
      };
    }
  }
}

class _RpcError implements Exception {
  _RpcError(this.code, this.message);
  final int code;
  final String message;
}
