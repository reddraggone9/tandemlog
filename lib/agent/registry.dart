import 'command.dart';
import 'commands_read.dart';
import 'commands_more.dart';
import 'commands_write.dart';

/// The single command registry: CLI, `schema` and MCP `tools/list` all derive
/// from this list.
final List<AgentCommand> registry = List.unmodifiable([
  initCommand(),
  ...readCommands(),
  ...writeCommands(),
  ...moreCommands(),
]);
