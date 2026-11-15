import 'package:flutter_test/flutter_test.dart';
import 'package:tandemlog/food/food_admission.dart';

void main() {
  test('Food admission memo binds every raw byte, ID and manifest', () {
    final source = {'a': 'raw-a', 'b': 'raw-b'};
    final original = FoodAdmissionInput('manifest', source);
    final reordered = FoodAdmissionInput('manifest', {
      'b': 'raw-b',
      'a': 'raw-a',
    });
    expect(original, reordered);
    expect(original.hashCode, reordered.hashCode);
    final memo = {original: 'admitted'};
    expect(memo[reordered], 'admitted');
    for (final changed in [
      FoodAdmissionInput('other-manifest', source),
      FoodAdmissionInput('manifest', {'a': 'raw-A', 'b': 'raw-b'}),
      FoodAdmissionInput('manifest', {'a': 'raw-a', 'c': 'raw-b'}),
      FoodAdmissionInput('manifest', {'a': 'raw-a'}),
    ]) {
      expect(changed, isNot(original));
      expect(memo[changed], isNull);
    }
    source['a'] = 'later mutation';
    expect(memo[reordered], 'admitted');
    expect(() => original.records['a'] = 'replace', throwsUnsupportedError);
  });
}
