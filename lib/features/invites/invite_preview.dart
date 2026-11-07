class InvitePreview {
  InvitePreview({
    required this.groupId,
    required this.groupName,
    required this.kind,
    required this.memberNames,
    required this.invitedBy,
    required this.expiresAt,
  });

  factory InvitePreview.fromRow(Map<String, dynamic> row) {
    final names = row['member_names'];
    return InvitePreview(
      groupId: row['group_id'] as String,
      groupName: row['group_name'] as String,
      kind: row['kind'] as String,
      memberNames: names is List
          ? names.cast<String>()
          : const <String>[],
      invitedBy: (row['invited_by'] as String?) ?? 'Alguém',
      expiresAt: DateTime.parse(row['expires_at'] as String).toLocal(),
    );
  }

  final String groupId;
  final String groupName;
  final String kind;
  final List<String> memberNames;
  final String invitedBy;
  final DateTime expiresAt;
}

class CreatedInvite {
  CreatedInvite({
    required this.inviteId,
    required this.code,
    required this.expiresAt,
  });

  factory CreatedInvite.fromRow(Map<String, dynamic> row) => CreatedInvite(
    inviteId: row['invite_id'] as String,
    code: row['code'] as String,
    expiresAt: DateTime.parse(row['expires_at'] as String).toLocal(),
  );

  final String inviteId;
  final String code;
  final DateTime expiresAt;
}
