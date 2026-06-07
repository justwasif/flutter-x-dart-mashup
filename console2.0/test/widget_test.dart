import 'package:console2_0/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('D-pad state maps to HID hat switch values', () {
    expect(const DpadState().hat, 8);
    expect(const DpadState(up: true).hat, 0);
    expect(const DpadState(up: true, right: true).hat, 1);
    expect(const DpadState(right: true).hat, 2);
    expect(const DpadState(right: true, down: true).hat, 3);
    expect(const DpadState(down: true).hat, 4);
    expect(const DpadState(down: true, left: true).hat, 5);
    expect(const DpadState(left: true).hat, 6);
    expect(const DpadState(left: true, up: true).hat, 7);
  });
}
