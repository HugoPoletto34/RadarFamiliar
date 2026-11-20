class Friend {
  Friend({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.createdAt,
  });

  factory Friend.fromRow(Map<String, dynamic> row) => Friend(
    userId: row['user_id'] as String,
    displayName: (row['display_name'] as String?)?.trim().isNotEmpty == true
        ? row['display_name'] as String
        : 'Sem nome',
    avatarUrl: row['avatar_url'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final DateTime createdAt;

  String get initial {
    final t = displayName.trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }
}

class FriendRequest {
  FriendRequest({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.outgoing,
    required this.createdAt,
  });

  factory FriendRequest.fromRow(Map<String, dynamic> row) {
    final kind = row['kind'] as String;
    return FriendRequest(
      userId: row['user_id'] as String,
      displayName: (row['display_name'] as String?)?.trim().isNotEmpty == true
          ? row['display_name'] as String
          : 'Sem nome',
      avatarUrl: row['avatar_url'] as String?,
      outgoing: kind == 'outgoing',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool outgoing;
  final DateTime createdAt;

  String get initial {
    final t = displayName.trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }
}

class FriendPreview {
  FriendPreview({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
  });

  factory FriendPreview.fromRow(Map<String, dynamic> row) => FriendPreview(
    userId: row['user_id'] as String,
    displayName: (row['display_name'] as String?)?.trim().isNotEmpty == true
        ? row['display_name'] as String
        : 'Sem nome',
    avatarUrl: row['avatar_url'] as String?,
  );

  final String userId;
  final String displayName;
  final String? avatarUrl;
}

class FriendsList {
  const FriendsList({
    required this.friends,
    required this.incoming,
    required this.outgoing,
  });

  final List<Friend> friends;
  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;
}

class GroupInvite {
  GroupInvite({
    required this.groupId,
    required this.groupName,
    required this.kind,
    required this.invitedBy,
    required this.invitedByName,
    required this.createdAt,
  });

  factory GroupInvite.fromRow(Map<String, dynamic> row) => GroupInvite(
    groupId: row['group_id'] as String,
    groupName: row['group_name'] as String,
    kind: row['kind'] as String,
    invitedBy: row['invited_by'] as String,
    invitedByName: (row['invited_by_name'] as String?) ?? 'Alguém',
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );

  final String groupId;
  final String groupName;
  final String kind;
  final String invitedBy;
  final String invitedByName;
  final DateTime createdAt;
}

class PendingGroupInvite {
  PendingGroupInvite({
    required this.inviteeId,
    required this.displayName,
    this.avatarUrl,
    required this.createdAt,
  });

  factory PendingGroupInvite.fromRow(Map<String, dynamic> row) =>
      PendingGroupInvite(
        inviteeId: row['invitee_id'] as String,
        displayName: (row['display_name'] as String?)?.trim().isNotEmpty == true
            ? row['display_name'] as String
            : 'Sem nome',
        avatarUrl: row['avatar_url'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );

  final String inviteeId;
  final String displayName;
  final String? avatarUrl;
  final DateTime createdAt;
}
