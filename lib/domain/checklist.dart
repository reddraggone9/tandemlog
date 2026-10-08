import 'package:uuid/uuid.dart';

import 'event.dart';
import 'projection.dart';

const maximumChecklistCopyItems = 1000;

bool isChecklistCreation(String type) =>
    type == 'checklist.itemCreated' || type == 'checklist.itemSeeded';

String copiedChecklistId(String successor, String source) =>
    const Uuid().v5(successor, 'checklist:$source');

/// Required additive copy meaning; old successor snapshots remain unchanged.
void validateChecklistCopy(Object? value, String successor) {
  if (value is! Map<String, dynamic> ||
      value.length != 4 ||
      !value.keys.toSet().containsAll({
        'codec',
        'adapter',
        'frontiers',
        'items',
      }) ||
      value['codec'] != 'yrs-v1' ||
      value['adapter'] != 2 ||
      value['items'] is! List ||
      (value['items'] as List).length > maximumChecklistCopyItems) {
    throw FormatFailure('Invalid checklist inheritance descriptor.');
  }
  final seen = <String>{};
  // Validate frontiers even for a legitimately empty observed checklist.
  validateTextBaseline({
    'codec': value['codec'],
    'adapter': 1,
    'frontiers': value['frontiers'],
    'seedDigest': '0' * 64,
  });
  if ((value['frontiers'] as Map).isEmpty) {
    throw FormatFailure('Checklist inheritance requires observed history.');
  }
  for (final item in value['items'] as List) {
    if (item is! Map<String, dynamic> ||
        item.length != 5 ||
        !item.keys.toSet().containsAll({
          'id',
          'source',
          'title',
          'description',
          'fields',
        }) ||
        !isCanonicalId(item['source']) ||
        item['id'] != copiedChecklistId(successor, item['source'] as String) ||
        !seen.add(item['source'] as String) ||
        item['title'] is! String ||
        (item['title'] as String).trim().isEmpty ||
        (item['title'] as String).length > 500 ||
        item['description'] is! String ||
        (item['description'] as String).length > 10000) {
      throw FormatFailure('Invalid copied checklist item.');
    }
    // The common frontier map above belongs to the whole copy, not each item.
    validateTextInheritanceFields(item['fields'], 2);
  }
}

/// An ordinary task contribution and an item copy share the native adapter;
/// they retain the real enclosing canonical record's ID/hash/clock.
class TextInheritanceContribution {
  const TextInheritanceContribution(
    this.event,
    this.parent,
    this.child,
    this.snapshot,
    this.proof, {
    this.checklist = false,
  });
  final LogEvent event;
  final String parent, child;
  final Map<String, dynamic> snapshot, proof;
  final bool checklist;
  String get key => checklist ? '${event.id}:$child' : event.id;
}

Iterable<TextInheritanceContribution> textContributions(
  Iterable<LogEvent> history,
  String entity,
) sync* {
  for (final event in history) {
    if (hasNativeTaskSuccessor(event) &&
        (event.data['successor'] as Map)['id'] == entity) {
      yield TextInheritanceContribution(
        event,
        event.entity,
        entity,
        event.data['successor'] as Map<String, dynamic>,
        event.data['inheritance'] as Map<String, dynamic>,
      );
    }
    if (event.type != 'task.completedWithChecklist') continue;
    final descriptor = event.data['checklist'] as Map;
    for (final raw in descriptor['items'] as List) {
      final item = raw as Map<String, dynamic>;
      if (item['id'] != entity) continue;
      yield TextInheritanceContribution(
        event,
        item['source'] as String,
        entity,
        item,
        {
          'codec': descriptor['codec'],
          'adapter': descriptor['adapter'],
          'frontiers': descriptor['frontiers'],
          'fields': item['fields'],
        },
        checklist: true,
      );
    }
  }
}

LogEvent checklistCopyCreation(
  LogEvent completion,
  Map<String, dynamic> item,
) => LogEvent(
  completion.space,
  completion.writer,
  completion.sequence,
  completion.clock,
  item['id'] as String,
  'checklist.itemSeeded',
  {
    'parent': (completion.data['successor'] as Map)['id'],
    'source': item['source'],
    'title': item['title'],
    'description': item['description'],
    'before': null,
  },
);

Map<String, dynamic>? projectChecklistItem(List<LogEvent> events) {
  events.sort(compareEvents);
  final creations = events
      .where((event) => isChecklistCreation(event.type))
      .toList();
  if (creations.isEmpty) return null;
  if (creations.length != 1 ||
      events.any(
        (event) =>
            event.type == 'task.created' ||
            event.type == 'task.createdWithText' ||
            event.type == 'user.created',
      )) {
    throw FormatFailure('Checklist identity collides with an entity creation.');
  }
  final seed = creations.single;
  final state = <String, dynamic>{
    'id': seed.entity,
    'kind': 'checklistItem',
    ...seed.data,
    'order': '${seed.clock.sortKey}:${seed.writer}',
    'completed': false,
  }..remove('text');
  final inactive = retractedOperationIds(events);
  for (final event in events) {
    if (event.type.startsWith('task.') &&
        !const {
          'task.textEdited',
          'task.textEditUndone',
          'task.operationUndone',
        }.contains(event.type)) {
      throw FormatFailure(
        'Task-only operation references a checklist item in ${event.id}.',
      );
    }
    if (event.type == 'task.textEdited' &&
        event.data.keys.any((key) => !{'changes', 'intent'}.contains(key))) {
      throw FormatFailure(
        'Checklist text accepts only title and notes in ${event.id}.',
      );
    }
    if (!inactive.contains(event.id) && event.type == 'checklist.itemEdited') {
      state['completed'] = event.data['completed'];
    }
  }
  state['deleted'] = events.any(
    (event) =>
        event.type == 'checklist.itemDeleted' && !inactive.contains(event.id),
  );
  return state;
}

/// Pure membership/order projection. Native field materialization is an adapter
/// step; this never appends copies or changes a historical completion.
List<Map<String, dynamic>> projectChecklist(
  List<LogEvent> history,
  String parent,
) {
  history.sort(compareEvents);
  final seeds = <String, List<LogEvent>>{};
  final initial = <String>[];
  for (final event in history) {
    if (event.type != 'task.completedWithChecklist' ||
        (event.data['successor'] as Map)['id'] != parent) {
      continue;
    }
    final copies = (event.data['checklist'] as Map)['items'] as List;
    for (final item in copies.cast<Map<String, dynamic>>()) {
      seeds
          .putIfAbsent(item['id'] as String, () => [])
          .add(checklistCopyCreation(event, item));
    }
    // Keep the first list's relative order; later-only items join next to their
    // next known sibling where possible. Child-owned moves apply below.
    for (var index = copies.length - 1; index >= 0; index--) {
      final id = (copies[index] as Map)['id'] as String;
      if (initial.contains(id)) continue;
      final next = index + 1 < copies.length
          ? (copies[index + 1] as Map)['id'] as String
          : null;
      initial.insert(
        next != null && initial.contains(next)
            ? initial.indexOf(next)
            : initial.length,
        id,
      );
    }
  }
  final creations = history.where(
    (event) =>
        event.type == 'checklist.itemCreated' && event.data['parent'] == parent,
  );
  final ids = {...seeds.keys, ...creations.map((event) => event.entity)};
  final states = <String, Map<String, dynamic>>{};
  for (final id in ids) {
    final own = history.where((event) => event.entity == id).toList();
    if (seeds.containsKey(id)) own.add(seeds[id]!.first);
    final state = projectChecklistItem(own);
    if (state != null) states[id] = state;
  }
  final inactive = retractedOperationIds(history);
  final actions = <OrderAction>[
    for (final id in initial) OrderAction(id, 'task.created'),
    for (final event in history)
      if (creations.contains(event)) ...[
        OrderAction(event.entity, 'task.created'),
        OrderAction(
          event.entity,
          'task.moved',
          before: event.data['before'] as String?,
        ),
      ] else if (event.type == 'checklist.itemMoved' &&
          ids.contains(event.entity) &&
          !inactive.contains(event.id))
        OrderAction(
          event.entity,
          'task.moved',
          before: event.data['before'] as String?,
        ),
  ];
  return [
    for (final id in projectOrder(states.keys, actions))
      if (states[id]!['deleted'] != true) states[id]!,
  ];
}
