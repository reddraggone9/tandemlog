import 'package:flutter/material.dart';
import 'package:tandemlog/presentation/task_editor.dart';
import 'tag_entry_trials.dart';

void main() => runApp(const TagTrialsApp());

class TagTrialsApp extends StatefulWidget {
  const TagTrialsApp({super.key});
  @override
  State<TagTrialsApp> createState() => _TagTrialsAppState();
}

class _TagTrialsAppState extends State<TagTrialsApp> {
  int option = const int.fromEnvironment('TAG_TRIAL_OPTION');
  bool bulk = const bool.fromEnvironment('TAG_TRIAL_BULK');
  String saved = '';
  static const tags = [
    'backlog',
    'backyard',
    'banking',
    'home',
    'household/repairs',
    'Shopping',
    'shopping/groceries',
    'weekend',
    'work',
  ];
  Map<String, dynamic> task(String id) => {
    'id': id,
    'title': 'Prepare the weekend garden jobs',
    'description': 'Check the tools and order the missing supplies.',
    'tags': ['home'],
    'schedule': <String, dynamic>{},
    'completed': false,
  };

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff267461),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: colors.surface,
        inputDecorationTheme: InputDecorationTheme(
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: colors.surfaceContainerLowest,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Tag entry trials')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('A · Text completion'),
                    selected: option == 0,
                    onSelected: (_) => setState(() {
                      option = 0;
                      saved = '';
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('B · Chips + query'),
                    selected: option == 1,
                    onSelected: (_) => setState(() {
                      option = 1;
                      saved = '';
                    }),
                  ),
                  FilterChip(
                    label: const Text('Bulk entry'),
                    selected: bulk,
                    onSelected: (value) => setState(() {
                      bulk = value;
                      saved = '';
                    }),
                  ),
                ],
              ),
            ),
            if (saved.isNotEmpty)
              Padding(padding: const EdgeInsets.all(8), child: Text(saved)),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 560,
                  child: bulk
                      ? BulkTaskEditor(
                          key: ValueKey('bulk-$option'),
                          panel: true,
                          onClose: () {},
                          tasks: [task('one'), task('two')],
                          tagEntryTrialBuilder: builder,
                          onSave: (edit) async => setState(() {
                            saved =
                                'Preview only · Add ${edit.addTags.join(', ')}; '
                                'remove ${edit.removeTags.join(', ')}';
                          }),
                        )
                      : TaskEditor(
                          key: ValueKey('single-$option'),
                          panel: true,
                          onClose: () {},
                          task: task('one'),
                          tagEntryTrialBuilder: builder,
                          save: (fields, added, removed) async => setState(() {
                            saved =
                                'Preview only · Added ${added.join(', ')}; '
                                'removed ${removed.join(', ')}';
                          }),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget builder(
    String field,
    String label,
    TextEditingController controller,
    bool enabled,
  ) => TagEntryTrial(
    key: ValueKey('trial-$field-$option'),
    controller: controller,
    label: label,
    field: field,
    inventory: tags,
    chips: option == 1,
    enabled: enabled,
  );
}
