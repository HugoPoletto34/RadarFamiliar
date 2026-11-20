import 'package:flutter/widgets.dart';

import '../../features/friends/services/friend_service.dart';
import '../../features/radar/services/radar_service.dart';
import '../location/location_service.dart';
import '../push/push_service.dart';

/// Disponibiliza os serviços compartilhados para a árvore de widgets,
/// sem depender de libs de state management.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.radarService,
    required this.friendService,
    required this.locationService,
    this.pushService,
    required super.child,
  });

  final RadarService radarService;
  final FriendService friendService;
  final LocationService locationService;
  final PushService? pushService;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope não encontrado na árvore de widgets.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      radarService != oldWidget.radarService ||
      friendService != oldWidget.friendService ||
      locationService != oldWidget.locationService ||
      pushService != oldWidget.pushService;
}
