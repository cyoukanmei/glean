import 'package:flutter_test/flutter_test.dart';
import 'package:glean/features/vocab/ui/word_sheet.dart';

void main() {
  test('splits parts of speech from meanings', () {
    expect(definitionLines('vt. 放弃, 抛弃\nn. 放任, 无拘束'), [
      ('vt.', '放弃, 抛弃'),
      ('n.', '放任, 无拘束'),
    ]);
  });

  test('keeps lines without a part of speech and drops domain notes', () {
    // ECDICT sometimes carries a literal "\r" before the line break.
    expect(definitionLines('第一个字母 A; 一个\\r\n[计] 累加器'), [(null, '第一个字母 A; 一个')]);
    expect(definitionLines('[计] 设备'), [(null, '[计] 设备')]);
  });

  test('caps the number of lines', () {
    expect(definitionLines('n. a\nv. b\nadj. c\nadv. d'), hasLength(3));
  });
}
