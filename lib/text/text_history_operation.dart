import '../domain/event.dart';
import '../domain/text_actor.dart';
import 'native_text_engine.dart';

/// An original packet and its original authorship. Inheritance grants permission
/// to reuse the packet; it does not make its completing writer the author.
class LineageTextOperation {
  const LineageTextOperation(this.event, this.field, this.claim, this.update);
  final LogEvent event;
  final String field;
  final TextActorClaim claim;
  final NativeTextUpdate update;
}
