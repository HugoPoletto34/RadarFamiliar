import 'package:flutter_test/flutter_test.dart';
import 'package:radar_familiar/core/auth/auth_redirect.dart';
import 'package:radar_familiar/core/invites/invite_link.dart';
import 'package:radar_familiar/features/invites/services/invite_actions.dart';

void main() {
  test('parseia code do deep link', () {
    final uri = Uri.parse('radarfamiliar://invite/abcd2345');
    expect(inviteCodeFromUri(uri), 'ABCD2345');
  });

  test('parseia o formato antigo com query', () {
    final uri = Uri.parse('br.com.radarfamiliar://invite?code=abcd2345');
    expect(inviteCodeFromUri(uri), 'ABCD2345');
  });

  test('ignora outros hosts', () {
    final uri = Uri.parse('br.com.radarfamiliar://login-callback');
    expect(inviteCodeFromUri(uri), isNull);
  });

  test('mensagem isola o link sem scheme de domínio', () {
    const code = 'ABCD2345';
    final link = AuthRedirect.inviteLink(code);
    final message = inviteShareMessage(code: code, link: link);
    expect(link, 'radarfamiliar-dev://invite/ABCD2345');
    expect(message, contains('\n$link\n'));
    expect(message, isNot(contains('br.com.radarfamiliar')));
    expect(link, isNot(contains('?')));
  });
}
