import 'package:flutter/widgets.dart';

import '../../features/invites/services/invite_service.dart';
import '../../features/radar/services/radar_service.dart';
import '../location/location_service.dart';
import '../push/push_service.dart';

/// Disponibiliza os serviços compartilhados para a árvore de widgets,
/// sem depender de libs de state management.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.radarService,
    required this.inviteService,
    required this.locationService,
    this.pushService,
    required super.child,
  });

  final RadarService radarService;
  final InviteService inviteService;
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
      inviteService != oldWidget.inviteService ||
      locationService != oldWidget.locationService ||
      pushService != oldWidget.pushService;
}
