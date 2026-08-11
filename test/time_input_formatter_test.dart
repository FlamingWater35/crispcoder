import 'package:crispcoder/features/editor/widgets/tabs/quick_edit_tab.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = TimeInputFormatter();

  TextEditingValue edit(String input, {String old = ''}) {
    return formatter.formatEditUpdate(
      TextEditingValue(text: old),
      TextEditingValue(text: input),
    );
  }

  test('formats digits into HH:MM:SS with auto colons', () {
    expect(edit('12').text, '12');
    expect(edit('1234').text, '12:34');
    expect(edit('123456').text, '12:34:56');
  });

  test('strips non-digit characters', () {
    expect(edit('abc').text, '');
    expect(edit('1a2b3c').text, '12:3');
    expect(edit('12:34:56').text, '12:34:56'); // pasted formatted value
  });

  test('caps at 6 digits (HH:MM:SS)', () {
    expect(edit('1234567').text, '12:34:56');
    expect(edit('99999999').text, '99:99:99');
  });
}
