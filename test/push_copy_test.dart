import 'package:flutter_test/flutter_test.dart';
import 'package:radar_familiar/core/push/push_copy.dart';

void main() {
  test('quem entra no grupo', () {
    final text = pushText('member_joined', {'member_name': 'Ana'});
    expect(text.title, 'Novo integrante');
    expect(text.body, 'Ana entrou no grupo');
  });

  test('entrada sem nome', () {
    final text = pushText('member_joined', {});
    expect(text.body, 'Alguém entrou no grupo');
  });

  test('pedido de amizade', () {
    final text = pushText('friend_request', {'friend_name': 'Carlos'});
    expect(text.title, 'Pedido de amizade');
    expect(text.body, 'Carlos quer ser seu amigo');
  });

  test('amizade aceita', () {
    final text = pushText('friend_accepted', {'friend_name': 'Ana'});
    expect(text.title, 'Amizade aceita');
    expect(text.body, 'Ana aceitou seu pedido');
  });

  test('convite de grupo', () {
    final text = pushText('group_invite', {
      'invited_by_name': 'Ana',
      'group_name': 'Família',
    });
    expect(text.title, 'Convite de grupo');
    expect(text.body, 'Ana convidou você para Família');
  });

  test('alerta com quem criou e o lugar', () {
    final text = pushText('alert_created_about_you', {
      'watcher_name': 'Bruno',
      'place_name': 'Casa',
    });
    expect(text.title, 'Alerta sobre você');
    expect(text.body, 'Bruno criou um alerta em Casa');
  });

  test('tipo desconhecido usa o texto que veio no payload', () {
    final text = pushText('outro', {'title': 'Oi', 'body': 'Tudo bem'});
    expect(text.title, 'Oi');
    expect(text.body, 'Tudo bem');
  });

  test('payload do toque volta inteiro', () {
    const data = {'type': 'member_joined', 'group_id': 'abc'};
    expect(decodePushPayload(encodePushPayload(data)), data);
    expect(decodePushPayload('não é json'), isNull);
    expect(decodePushPayload(''), isNull);
  });
}
