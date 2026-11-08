import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/missing_config_app.dart';
import 'core/location/location_service.dart';
import 'core/push/push_bootstrap.dart';
import 'core/push/push_service.dart';
import 'core/supabase/supabase_bootstrap.dart';
import 'features/invites/services/invite_service.dart';
import 'features/radar/services/radar_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.hasSupabase) {
    runApp(const MissingConfigApp());
    return;
  }
  await initSupabase();
  final pushOn = await initPush();

  final client = Supabase.instance.client;
  final push = pushOn ? PushService(client) : null;
  if (push != null) await push.start();
  runApp(
    RadarFamiliarApp(
      radarService: RadarService(client),
      inviteService: InviteService(client),
      locationService: LocationService(),
      pushService: push,
    ),
  );
}
