import 'package:flutter_test/flutter_test.dart';
import 'package:radar_familiar/features/radar/models/radar_group.dart';

void main() {
  group('RadarGroup.validateName', () {
    test('rejeita nome vazio ou só espaços', () {
      expect(RadarGroup.validateName(''), isNotNull);
      expect(RadarGroup.validateName('   '), isNotNull);
    });

    test('aceita nome com 1 a 60 caracteres', () {
      expect(RadarGroup.validateName('A'), isNull);
      expect(RadarGroup.validateName('Família Silva'), isNull);
      expect(RadarGroup.validateName('x' * 60), isNull);
    });

    test('rejeita nome com mais de 60 caracteres', () {
      expect(RadarGroup.validateName('x' * 61), isNotNull);
    });

    test('ignora espaços nas pontas na contagem', () {
      expect(RadarGroup.validateName('  Casa  '), isNull);
      expect(RadarGroup.validateName(' ${'x' * 61} '), isNotNull);
    });
  });

  group('GroupKind', () {
    test('rótulos em português', () {
      expect(GroupKind.family.label, 'Família');
      expect(GroupKind.friends.label, 'Amigos');
    });

    test('valores da API', () {
      expect(GroupKind.family.apiValue, 'family');
      expect(GroupKind.friends.apiValue, 'friends');
    });

    test('parse a partir do banco', () {
      expect(GroupKind.parse('family'), GroupKind.family);
      expect(GroupKind.parse('friends'), GroupKind.friends);
      expect(() => GroupKind.parse('other'), throwsFormatException);
    });

    test('fromRow monta o modelo', () {
      final group = RadarGroup.fromRow({
        'id': 'abc',
        'name': 'Família',
        'kind': 'family',
      });
      expect(group.id, 'abc');
      expect(group.name, 'Família');
      expect(group.kind, GroupKind.family);
    });
  });
}
