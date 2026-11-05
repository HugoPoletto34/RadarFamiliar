/// Uma linha de `get_group_locations`: status e, se visível, a posição.
class MemberLocation {
  const MemberLocation({
    required this.userId,
    required this.name,
    required this.status,
    this.lat,
    this.lng,
    this.battery,
    this.lastSeenAt,
  });

  factory MemberLocation.fromRow(Map<String, dynamic> row) => MemberLocation(
    userId: row['user_id'] as String,
    name: (row['display_name'] as String?) ?? 'Sem nome',
    status: row['status'] as String,
    lat: (row['lat'] as num?)?.toDouble(),
    lng: (row['lng'] as num?)?.toDouble(),
    battery: (row['battery'] as num?)?.toInt(),
    lastSeenAt: DateTime.tryParse((row['last_seen_at'] as String?) ?? ''),
  );

  final String userId;
  final String name;

  /// 'sharing', 'paused' ou 'not_sharing'.
  final String status;
  final double? lat;
  final double? lng;
  final int? battery;
  final DateTime? lastSeenAt;

  bool get isSharing => status == 'sharing';
  bool get hasPosition => lat != null && lng != null;
  String get initial =>
      name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
}

class SharingState {
  const SharingState({required this.on, this.until});

  static const off = SharingState(on: false);

  final bool on;

  /// Nulo com [on] = compartilhando até desligar.
  final DateTime? until;

  bool get expired => on && until != null && DateTime.now().isAfter(until!);
}
