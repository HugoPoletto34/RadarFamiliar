/// Grupo do usuário (linhas de `groups` via membership).
class RadarGroup {
  const RadarGroup({required this.id, required this.name, required this.kind});

  factory RadarGroup.fromRow(Map<String, dynamic> row) => RadarGroup(
    id: row['id'] as String,
    name: row['name'] as String,
    kind: GroupKind.parse(row['kind'] as String),
  );

  final String id;
  final String name;
  final GroupKind kind;

  static const nameMinLength = 1;
  static const nameMaxLength = 60;

  /// Retorna mensagem de erro em português, ou `null` se o nome for válido.
  static String? validateName(String raw) {
    final name = raw.trim();
    if (name.length < nameMinLength) {
      return 'Informe um nome para o grupo.';
    }
    if (name.length > nameMaxLength) {
      return 'O nome pode ter no máximo $nameMaxLength caracteres.';
    }
    return null;
  }
}

enum GroupKind {
  family,
  friends;

  static GroupKind parse(String value) => switch (value) {
    'family' => GroupKind.family,
    'friends' => GroupKind.friends,
    _ => throw FormatException('Tipo de grupo desconhecido: $value'),
  };

  String get apiValue => switch (this) {
    GroupKind.family => 'family',
    GroupKind.friends => 'friends',
  };

  String get label => switch (this) {
    GroupKind.family => 'Família',
    GroupKind.friends => 'Amigos',
  };

  String get description => switch (this) {
    GroupKind.family =>
      'Dá para ver quem compartilha mesmo com o seu compartilhamento desligado.',
    GroupKind.friends => 'Só vê os outros quem também está compartilhando.',
  };
}
