import 'package:flutter/foundation.dart';

import '../models/friend.dart';
import '../services/friend_service.dart';

/// Estado da tela de amizades: código, amigos e pedidos.
class FriendsController extends ChangeNotifier {
  FriendsController(this._service);

  final FriendService _service;

  String? code;
  List<Friend> friends = const [];
  List<FriendRequest> incoming = const [];
  List<FriendRequest> outgoing = const [];
  bool loading = true;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _service.myFriendCode(),
        _service.listFriends(),
      ]);
      code = results[0] as String;
      final list = results[1] as FriendsList;
      friends = list.friends;
      incoming = list.incoming;
      outgoing = list.outgoing;
    } on Object catch (e) {
      error = friendErrorMessage(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> regenerateCode() async {
    code = await _service.regenerateFriendCode();
    notifyListeners();
  }

  Future<void> acceptRequest(String userId) async {
    await _service.respondFriendRequest(userId, accept: true);
    await load();
  }

  Future<void> declineRequest(String userId) async {
    await _service.respondFriendRequest(userId, accept: false);
    await load();
  }

  Future<void> cancelRequest(String userId) async {
    await _service.cancelFriendRequest(userId);
    await load();
  }

  Future<void> removeFriend(String userId) async {
    await _service.removeFriend(userId);
    await load();
  }
}
