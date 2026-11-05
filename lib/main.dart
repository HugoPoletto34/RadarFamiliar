import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/missing_config_app.dart';
import 'core/config/env.dart';
import 'core/push/push_bootstrap.dart';
import 'core/supabase/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Env.hasSupabase) {
    runApp(const MissingConfigApp());
    return;
  }
  await initSupabase();
  await initPush();
  runApp(const RadarFamiliarApp());
}
