import 'package:crispcoder/features/editor/widgets/tabs/quick_edit_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = TimeInputFormatter();

  TextEditingValue edit(String input, {String old = ''}) {
    return formatter.formatEditUpdate(
      TextEditingValue(text: old),
      TextEditingValue(text: input),
    );
  }

  test('right-aligns digits into HH:MM:SS with auto colons', () {
    // Single digits are seconds, 4 digits are MM:SS, 6 digits HH:MM:SS.
    expect(edit('5').text, '00:00:05');
    expect(edit('12').text, '00:00:12');
    expect(edit('1234').text, '00:12:34');
    expect(edit('123456').text, '12:34:56');
  });

  test('strips non-digit characters', () {
    expect(edit('abc').text, '');
    expect(edit('1a2b3c').text, '00:01:23'); // digits '123', right-aligned
    expect(edit('12:34:56').text, '12:34:56'); // pasted formatted value
  });

  test('caps at 6 digits (HH:MM:SS)', () {
    expect(edit('1234567').text, '12:34:56');
    expect(edit('99999999').text, '99:59:59');
  });

  test('clamps minutes and seconds to 0-59', () {
    expect(edit('99').text, '00:00:59');
    expect(edit('9999').text, '00:59:59');
    expect(edit('99999').text, '09:59:59');
  });
}
