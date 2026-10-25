import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'event_chain.dart';
import 'utf8_byte_limit.dart';

const currentOperationFormat = 1;
const _domain = 'tandemlog:operation:v1\n';
const _additionalNames = {'CST6CDT', 'EST5EDT', 'MST7MDT', 'PST8PDT'};
const _zoneFamilies = {'task.create', 'task.update', 'task.complete'};

bool operationUsesAdditionalZone(Object? value) {
  if (value is Map) {
    if (_additionalNames.contains(value['timeZone'])) return true;
    return value.values.any(operationUsesAdditionalZone);
  }
  return value is List && value.any(operationUsesAdditionalZone);
}

/// One current wire representation. Semantic reference identity is independent
/// of physical authorship; the unified chain covers both. Only sealed converted
/// prefixes may retain an anchor different from the current content hash.
class CurrentOperation {
  CurrentOperation({
    required this.module,
    required this.space,
    required this.author,
    required this.writer,
    required this.sequence,
    required this.clock,
    required this.subject,
    required this.family,
    required this.revision,
    required Map<String, dynamic> value,
    required this.predecessor,
    String? referenceHash,
  }) : value = _freezeOperationValue(value) as Map<String, dynamic>,
       retainedReferenceHash = referenceHash;
  final String module,
      space,
      author,
      writer,
      clock,
      subject,
      family,
      predecessor;
  final int sequence, revision;
  final Map<String, dynamic> value;
  final String? retainedReferenceHash;
  Map<String, dynamic> get _body => {
    'format': 'tandemlog.operation',
    'version': currentOperationFormat,
    'module': module,
    'space': space,
    'author': author,
    'identity': {'writer': writer, 'sequence': sequence},
    'clock': clock,
    'subject': subject,
    'operation': {'family': family, 'revision': revision},
    'value': value,
    'predecessor': predecessor,
  };
  late final String contentHash = sha256
      .convert(utf8.encode('$_domain${canonicalDataJson(_body)}'))
      .toString();
  String get referenceHash => retainedReferenceHash ?? contentHash;
  Map<String, dynamic> toJson() => {
    ..._body,
    'referenceHash': referenceHash,
    'contentHash': contentHash,
  };
  late final String _encoded = canonicalDataJson(toJson());
  String encode() => _encoded;

  static void _keys(Map value, Set<String> keys) {
    if (value.length != keys.length || !value.keys.every(keys.contains)) {
      throw const FormatException(
        'Unknown operation fields. Update the app; history was preserved.',
      );
    }
  }

  factory CurrentOperation.decode(String raw, {required String module}) {
    if (exceedsUtf8ByteLimit(raw, 1024 * 1024)) {
      throw const FormatException('Oversized current operation.');
    }
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> ||
        j['format'] != 'tandemlog.operation' ||
        j['version'] != currentOperationFormat ||
        j['module'] != module) {
      throw const FormatException(
        'Unsupported operation format. Update the app; history was preserved.',
      );
    }
    _keys(j, {
      'format',
      'version',
      'module',
      'space',
      'author',
      'identity',
      'clock',
      'subject',
      'operation',
      'value',
      'predecessor',
      'referenceHash',
      'contentHash',
    });
    final identity = j['identity'] as Map<String, dynamic>;
    final operation = j['operation'] as Map<String, dynamic>;
    _keys(identity, {'writer', 'sequence'});
    _keys(operation, {'family', 'revision'});
    final family = operation['family'] as String;
    final revision = operation['revision'] as int;
    final value = j['value'] as Map<String, dynamic>;
    if (revision != 1 &&
        !(revision == 2 &&
            module == 'tasks' &&
            _zoneFamilies.contains(family))) {
      throw const FormatException(
        'Unsupported required operation revision. Update the app; history was preserved.',
      );
    }
    if (operationUsesAdditionalZone(value) &&
        (revision < 2 || !_zoneFamilies.contains(family))) {
      throw const FormatException(
        'Additional time zone requires its operation revision.',
      );
    }
    if (j['clock'] is! String) {
      throw const FormatException('Clock must be a canonical decimal string.');
    }
    final result = CurrentOperation(
      module: module,
      space: j['space'] as String,
      author: j['author'] as String,
      writer: identity['writer'] as String,
      sequence: identity['sequence'] as int,
      clock: j['clock'] as String,
      subject: j['subject'] as String,
      family: family,
      revision: revision,
      value: value,
      predecessor: j['predecessor'] as String,
      referenceHash: j['referenceHash'] as String,
    );
    final id = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );
    if (![
          result.space,
          result.author,
          result.writer,
          result.subject,
        ].every(id.hasMatch) ||
        result.sequence < 1 ||
        result.sequence > 9007199254740991 ||
        !isEventHash(result.predecessor) ||
        !isEventHash(result.referenceHash) ||
        result.contentHash != j['contentHash'] ||
        result.encode() != raw) {
      throw const FormatException(
        'Current operation identity, hash or canonical bytes differ.',
      );
    }
    return result;
  }
}

// Hash/encoding reuse requires ownership of every JSON collection. Preserve
// unsupported leaves/keys for the unchanged canonical encoder to reject.
Object? _freezeOperationValue(Object? value) => switch (value) {
  Map<String, dynamic>() => Map<String, dynamic>.unmodifiable(
    value.map((key, item) => MapEntry(key, _freezeOperationValue(item))),
  ),
  Map() => Map.unmodifiable(
    value.map((key, item) => MapEntry(key, _freezeOperationValue(item))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freezeOperationValue)),
  _ => value,
};

class TaskOperationPayload {
  const TaskOperationPayload(this.family, this.value);
  final String family;
  final Map<String, dynamic> value;
}

/// Internal domain action names are not accepted as wire event types. These
/// adapters normalize related command representations into one current family.
/// A domain action must not gain a different meaning by losing fields during
/// normalization. New semantics require a new required family/revision.
void validateTaskActionFields(String type, Map<String, dynamic> data) {
  final allowed = switch (type) {
    'user.created' => {'name'},
    'task.created' => {'title', 'description', 'assignee', 'schedule', 'tags'},
    'task.createdWithText' => {
      'title',
      'description',
      'assignee',
      'schedule',
      'tags',
      'text',
    },
    'task.edited' => {
      'title',
      'description',
      'assignee',
      'schedule',
      'tagChanges',
    },
    'task.textEdited' => {
      'changes',
      'intent',
      'assignee',
      'schedule',
      'tagChanges',
    },
    'task.completed' => {'completedAt', 'successor'},
    'task.completedWithText' => {'completedAt', 'successor', 'inheritance'},
    'task.completedWithChecklist' => {
      'completedAt',
      'successor',
      'inheritance',
      'checklist',
    },
    'task.completedKeepingSuccessor' => {'completedAt', 'retainedSuccessor'},
    'task.completionUndone' ||
    'task.recurringCompletionUndone' => {'completion'},
    'task.operationUndone' => {'operation'},
    'task.textEditUndone' => {'operation', 'changes'},
    'text.baselineInitialized' => {
      'codec',
      'adapter',
      'frontiers',
      'seedDigest',
    },
    'task.deleted' || 'checklist.itemDeleted' => <String>{},
    'task.moved' || 'checklist.itemMoved' => {'before'},
    'checklist.itemCreated' => {
      'parent',
      'title',
      'description',
      'before',
      'text',
    },
    'checklist.itemEdited' => {'completed'},
    _ => throw const FormatException(
      'Unknown required Task action. Update the app.',
    ),
  };
  if (data.keys.any((k) => !allowed.contains(k)) ||
      type == 'task.createdWithText' && !data.containsKey('text') ||
      type == 'task.textEdited' && !data.containsKey('changes')) {
    throw const FormatException(
      'Unknown or missing required Task fields. Update the app; history was preserved.',
    );
  }
}

TaskOperationPayload normalizeTaskAction(
  String type,
  Map<String, dynamic> data,
) {
  validateTaskActionFields(type, data);
  Map<String, dynamic> without(Set<String> keys) =>
      Map.fromEntries(data.entries.where((entry) => !keys.contains(entry.key)));
  return switch (type) {
    'user.created' => TaskOperationPayload('person.create', {
      'name': data['name'],
    }),
    'task.created' || 'task.createdWithText' => TaskOperationPayload(
      'task.create',
      {
        'values': without({'text'}),
        if (data.containsKey('text')) 'textSeed': data['text'],
      },
    ),
    'task.edited' || 'task.textEdited' => TaskOperationPayload('task.update', {
      'values': without({'changes', 'intent', 'tagChanges'}),
      if (data.containsKey('changes')) 'text': data['changes'],
      if (data.containsKey('intent')) 'textIntent': data['intent'],
      if (data.containsKey('tagChanges')) 'tags': data['tagChanges'],
    }),
    'task.completed' ||
    'task.completedWithText' ||
    'task.completedWithChecklist' ||
    'task.completedKeepingSuccessor' => TaskOperationPayload('task.complete', {
      'mode': switch (type) {
        'task.completedWithText' => 'text',
        'task.completedWithChecklist' => 'checklist',
        'task.completedKeepingSuccessor' => 'retained',
        _ => 'snapshot',
      },
      'values': data,
    }),
    'task.completionUndone' ||
    'task.recurringCompletionUndone' ||
    'task.operationUndone' => TaskOperationPayload('task.retract', {
      'mode': switch (type) {
        'task.completionUndone' => 'completion',
        'task.recurringCompletionUndone' => 'recurrence',
        _ => 'operation',
      },
      'reference':
          data[type == 'task.operationUndone' ? 'operation' : 'completion'],
    }),
    'task.textEditUndone' => TaskOperationPayload('text.compensate', data),
    'text.baselineInitialized' => TaskOperationPayload('text.initialize', data),
    'task.deleted' => TaskOperationPayload('task.delete', data),
    'task.moved' => TaskOperationPayload('task.move', data),
    'checklist.itemCreated' => TaskOperationPayload('item.create', data),
    'checklist.itemEdited' => TaskOperationPayload('item.update', data),
    'checklist.itemMoved' => TaskOperationPayload('item.move', data),
    'checklist.itemDeleted' => TaskOperationPayload('item.delete', data),
    _ => throw const FormatException(
      'Unknown required Task action. Update the app; history was preserved.',
    ),
  };
}

(String, Map<String, dynamic>) taskActionFromCurrent(CurrentOperation op) {
  final d = op.value;
  void keys(Set<String> required, Set<String> optional) {
    if (!required.every(d.containsKey) ||
        d.keys.any(
          (key) => !required.contains(key) && !optional.contains(key),
        )) {
      throw const FormatException(
        'Unknown required Task payload. Update the app; history was preserved.',
      );
    }
  }

  switch (op.family) {
    case 'person.create':
      keys({'name'}, {});
      return ('user.created', {'name': d['name']});
    case 'task.create':
      keys({'values'}, {'textSeed'});
      if ((d['values'] as Map).containsKey('text')) {
        throw const FormatException(
          'Text seed cannot be shadowed inside values.',
        );
      }
      return (
        d.containsKey('textSeed') ? 'task.createdWithText' : 'task.created',
        {
          ...(d['values'] as Map<String, dynamic>),
          if (d.containsKey('textSeed')) 'text': d['textSeed'],
        },
      );
    case 'task.update':
      keys({'values'}, {'text', 'textIntent', 'tags'});
      if ((d['values'] as Map).keys.any(
        {'changes', 'intent', 'tagChanges'}.contains,
      )) {
        throw const FormatException(
          'Task contributions cannot be shadowed inside values.',
        );
      }
      return (
        d.containsKey('text') ? 'task.textEdited' : 'task.edited',
        {
          ...(d['values'] as Map<String, dynamic>),
          if (d.containsKey('text')) 'changes': d['text'],
          if (d.containsKey('textIntent')) 'intent': d['textIntent'],
          if (d.containsKey('tags')) 'tagChanges': d['tags'],
        },
      );
    case 'task.complete':
      keys({'mode', 'values'}, {});
      final type = switch (d['mode']) {
        'snapshot' => 'task.completed',
        'text' => 'task.completedWithText',
        'checklist' => 'task.completedWithChecklist',
        'retained' => 'task.completedKeepingSuccessor',
        _ => throw const FormatException(
          'Unknown Task completion semantics. Update the app.',
        ),
      };
      return (type, Map<String, dynamic>.from(d['values'] as Map));
    case 'task.retract':
      keys({'mode', 'reference'}, {});
      final type = switch (d['mode']) {
        'operation' => 'task.operationUndone',
        'completion' => 'task.completionUndone',
        'recurrence' => 'task.recurringCompletionUndone',
        _ => throw const FormatException(
          'Unknown Task retraction semantics. Update the app.',
        ),
      };
      return (
        type,
        {
          type == 'task.operationUndone' ? 'operation' : 'completion':
              d['reference'],
        },
      );
    default:
      final type = const {
        'text.compensate': 'task.textEditUndone',
        'text.initialize': 'text.baselineInitialized',
        'task.delete': 'task.deleted',
        'task.move': 'task.moved',
        'item.create': 'checklist.itemCreated',
        'item.update': 'checklist.itemEdited',
        'item.move': 'checklist.itemMoved',
        'item.delete': 'checklist.itemDeleted',
      }[op.family];
      if (type == null) {
        throw const FormatException(
          'Unknown required Task family. Update the app; history was preserved.',
        );
      }
      return (type, Map<String, dynamic>.from(d));
  }
}
