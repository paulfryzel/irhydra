library ir;

import 'package:irhydra/src/modes/ir.dart' as IR;
import 'package:unittest/unittest.dart';

void main() {
  group('Name', () {
    test('fullName named constructor', () {
      var str = 'foo';
      var name = new IR.Name.fromFull(str);

      expect(name.full, str, reason: 'to have a full name');
      expect(name.source, str, reason: 'to have a source');
      expect(name.short, null, reason: 'to not have a short name');
    });

    test('double equal operator override', () {
      var str = 'foo';
      var name1 = new IR.Name(str, str, str);
      var name2 = new IR.Name(str, null, null);
      var name3 = new IR.Name('bar', str, str);

      expect(name1 == name2, true, reason: 'to pass if full form matches');
      expect(name1 == name3, false, reason: 'to fail if full form differs');
    });
  });

  group('Deopt', () {
    test('', () {});
  });
}