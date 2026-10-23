import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/articles/ui/labels.dart';

void main() {
  test('compact counts in the Chinese style', () {
    expect(compactCount(0), '0');
    expect(compactCount(9999), '9999');
    expect(compactCount(10000), '1万');
    expect(compactCount(12345), '1.2万');
    expect(compactCount(123456), '12万');
  });
}
