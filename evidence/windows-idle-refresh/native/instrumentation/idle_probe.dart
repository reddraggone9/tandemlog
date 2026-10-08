import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

// TEST-ONLY observation. Does not request frames, invalidate, or poll.
void idleProbe(String phase, [Map<String, Object?> data = const {}]) {
  final path = Platform.environment['TANDEMLOG_IDLE_TRACE'];
  final profile = Platform.environment['TANDEMLOG_PROFILE'];
  if (path == null ||
      Platform.environment['TANDEMLOG_IDLE_PROBE'] != 'synthetic-only' ||
      profile != '${File(path).parent.path}/profile' ||
      !path.contains('/evidence/windows-idle-refresh/native/run-')) return;
  File(path).writeAsStringSync('${jsonEncode({
    'utc': DateTime.now().toUtc().toIso8601String(),
    'phase': phase,
    'lifecycle': SchedulerBinding.instance.lifecycleState?.name,
    'framesEnabled': SchedulerBinding.instance.framesEnabled,
    ...data,
  })}\n', mode: FileMode.append);
}
void idleFrame(String reason) {
  WidgetsBinding.instance.addPostFrameCallback((stamp) {
    idleProbe('postFrame', {'reason': reason, 'frameMicros': stamp.inMicroseconds});
  });
}
class IdlePaintProbe extends SingleChildRenderObjectWidget {
  const IdlePaintProbe({super.key, required this.label, required super.child});
  final String label;
  @override
  RenderObject createRenderObject(BuildContext context) => _IdlePaint(label);
  @override
  void updateRenderObject(BuildContext context, covariant _IdlePaint renderObject) {
    // No markNeedsPaint: rely solely on the production child's normal pipeline.
    renderObject.label = label;
  }
}
class _IdlePaint extends RenderProxyBox {
  _IdlePaint(this.label);
  String label;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    idleProbe('paint', {'entityMarker': label});
  }
}
