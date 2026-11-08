import 'package:flutter_test/flutter_test.dart';
import 'package:radar_familiar/features/radar/models/member_location.dart';
import 'package:radar_familiar/features/radar/widgets/share_sheet.dart';

void main() {
  final now = DateTime(2026, 11, 8, 12);

  test('prazo contínuo não tem contagem', () {
    const state = SharingState(on: true);
    expect(
      sharingDurationLabel(state, now: now),
      'Compartilhando até desligar',
    );
  });

  test('mostra os minutos que ainda faltam', () {
    final state = SharingState(
      on: true,
      until: now.add(const Duration(minutes: 45)),
    );
    expect(sharingDurationLabel(state, now: now), '45 min de compartilhamento');
  });

  test('mostra horas e minutos', () {
    final state = SharingState(
      on: true,
      until: now.add(const Duration(hours: 1, minutes: 5)),
    );
    expect(
      sharingDurationLabel(state, now: now),
      '1 h 5 min de compartilhamento',
    );
  });

  test('prazo vencido não conta como ativo', () {
    final state = SharingState(
      on: true,
      until: now.subtract(const Duration(minutes: 1)),
    );
    expect(sharingDurationLabel(state, now: now), 'Não está compartilhando');
  });

  test('lê o modo gravado no grupo', () {
    expect(sharingStateFromRow(null), SharingState.off);
    expect(
      sharingStateFromRow({'mode': 'continuous', 'temporary_until': null}),
      const SharingState(on: true),
    );
    final until = DateTime.utc(2026, 11, 8, 15);
    final temporary = sharingStateFromRow({
      'mode': 'temporary',
      'temporary_until': until.toIso8601String(),
    });
    expect(temporary.on, isTrue);
    expect(temporary.until, until.toLocal());
  });
}
