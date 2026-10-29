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

  /// One JSON-RPC message. Malformed input gets a JSON-RPC error and never
  /// stops the server; batches are not supported.
  Future<Map<String, Object?>?> handle(String line) async {
    Object? id;
    try {
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException catch (e) {
        throw _RpcError(-32700, 'Parse error: ${e.message}');
      }
      if (decoded is! Map) {
        throw _RpcError(
          -32600,
          decoded is List
              ? 'Batch requests are not supported.'
              : 'A request must be a JSON object.',
        );
      }
      final message = decoded.cast<String, Object?>();
      id = message['id'];
      if (id != null && id is! String && id is! num) {
        id = null;
        throw _RpcError(-32600, 'Invalid request id.');
      }
      final method = message['method'];
      if (method is! String) {
        if (id == null) return null;
        throw _RpcError(-32600, 'Missing method.');
      }
      final rawParams = message['params'];
      if (rawParams != null && rawParams is! Map) {
        if (id == null) return null;
        throw _RpcError(-32602, 'params must be an object.');
      }
      final params = (rawParams as Map?)?.cast<String, Object?>() ?? {};
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
                  'destructiveHint': c.destructive,
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
    } catch (e) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32603, 'message': 'Internal error: $e'},
      };
    }
  }

  Future<Map<String, Object?>> _call(Map<String, Object?> params) async {
    final name = params['name'];
    final command = registry
        .where((c) => c.toolName == name && c.kind != CommandKind.setup)
        .firstOrNull;
    if (command == null) throw _RpcError(-32602, 'Unknown tool $name');
    final arguments = params['arguments'];
    if (arguments != null && arguments is! Map) {
      throw _RpcError(-32602, 'arguments must be an object.');
    }
    try {
      final args = command.validate(
        Map<String, Object?>.from((arguments as Map?) ?? {}),
      );
      final env = environment ?? Platform.environment;
      final options = AgentOptions(
        profile: profile,
        timeZone: await hostZone(env, timeZone),
        environment: env,
      );
      final result = await execute(command, args, options);
      // The same 32 KB cap and resumable `next` as CLI JSON output.
      final structured =
          jsonDecode(
                capJson(
                  {'v': agentOutputVersion, ...result.data},
                  nextAfter: result.nextAfter,
                  nextWithinFirst: result.nextWithinFirst,
                ),
              )
              as Map<String, Object?>;
      return {
        'content': [
          {'type': 'text', 'text': _capText(result.text)},
        ],
        'structuredContent': structured,
        'isError': result.exitCode != 0,
      };
    } catch (e) {
      final f = AgentWorkspace.translate(e);
      final failure = f is AgentFailure ? f : AgentFailure('internal', '$f');
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

String _capText(String text) {
  final bytes = utf8.encode(text);
  if (bytes.length <= outputCapBytes) return text;
  final cut = utf8.decode(
    bytes.sublist(0, outputCapBytes - 128),
    allowMalformed: true,
  );
  return '$cut\n\u2026 truncated at 32 KB; see structuredContent';
}

class _RpcError implements Exception {
  _RpcError(this.code, this.message);
  final int code;
  final String message;
}
