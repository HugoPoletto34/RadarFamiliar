import 'package:flutter_test/flutter_test.dart';
import 'package:radar_familiar/core/auth/auth_redirect.dart';

void main() {
  test('AuthRedirect usa scheme dev fora de prod', () {
    expect(AuthRedirect.uri, 'br.com.radarfamiliar.dev://login-callback');
    expect(
      AuthRedirect.inviteLink('ABCD2345'),
      'br.com.radarfamiliar.dev://invite?code=ABCD2345',
    );
  });
}
