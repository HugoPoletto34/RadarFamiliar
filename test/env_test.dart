import 'package:flutter_test/flutter_test.dart';
import 'package:radar_familiar/core/config/env.dart';

void main() {
  test('flavor padrão é dev quando nada é injetado', () {
    expect(Env.flavor, 'dev');
    expect(Env.isProd, isFalse);
  });
}
