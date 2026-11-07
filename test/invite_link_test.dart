import 'package:flutter_test/flutter_test.dart';
import 'package:radar_familiar/core/invites/invite_link.dart';

void main() {
  test('parseia code do deep link', () {
    final uri = Uri.parse('br.com.radarfamiliar://invite?code=abcd2345');
    expect(inviteCodeFromUri(uri), 'ABCD2345');
  });

  test('ignora outros hosts', () {
    final uri = Uri.parse('br.com.radarfamiliar://login-callback');
    expect(inviteCodeFromUri(uri), isNull);
  });
}
