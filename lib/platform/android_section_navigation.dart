import 'package:flutter/services.dart';
import '../storage/local_settings.dart' show AppSection;

/// Only constant section destinations cross this channel. The host queues
/// navigation behind setup, commands and draft guards; this adapter owns no UI.
class AndroidSectionNavigation {
  AndroidSectionNavigation({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('tandemlog/sections');
  final MethodChannel _channel;
  var _highestId = 0, _manualRevision = 0;
  bool _disposed = false;

  Future<void> start(void Function(AppSection) onRequest) async {
    void accept(Object? arguments) {
      if (_disposed || arguments is! Map) return;
      final id = arguments['id'];
      final section = switch (arguments['section']) {
        'tasks' => AppSection.tasks,
        'food' => AppSection.food,
        _ => null,
      };
      if (id is! int || id <= _highestId || section == null) return;
      _highestId = id;
      onRequest(section);
    }

    // A warm request can arrive while the initial request is in flight.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openSection') accept(call.arguments);
    });
    final revision = _manualRevision;
    try {
      final initial = await _channel.invokeMethod<Object?>('takeInitial');
      if (revision == _manualRevision) accept(initial);
    } on MissingPluginException {
      // Desktop and older native hosts retain ordinary section navigation.
    } on PlatformException {
      // A launcher adapter failure must not prevent ordinary app setup.
    }
  }

  void manualNavigation() => _manualRevision++;
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }
}
