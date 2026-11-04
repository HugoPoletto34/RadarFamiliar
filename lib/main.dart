import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/push/push_bootstrap.dart';
import 'core/supabase/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  await initPush();
  runApp(const RadarFamiliarApp());
}
