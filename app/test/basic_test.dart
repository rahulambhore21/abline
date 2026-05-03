import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Basic App Tests', () {
    test('Environment validation', () {
      const bool isProduction = bool.fromEnvironment('dart.vm.product');
      expect(isProduction, isFalse); // Tests run in debug/jit mode
    });
  });
}
