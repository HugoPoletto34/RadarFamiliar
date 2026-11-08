import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_copy.dart';

/// Mesmo id enviado pela Edge Function e declarado no AndroidManifest.
const pushChannelId = 'radar_familiar';
const pushChannelName = 'Radar Familiar';
const pushChannelDescription = 'Avisos de grupos e alertas.';

const _androidIcon = '@drawable/ic_stat_radar';

/// Mensagem recebida com o app fechado ou em segundo plano.
/// O bloco `notification` já é exibido pelo sistema; aqui só entram
/// mensagens só de dados, para não duplicar o aviso.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  if (message.notification != null) return;

  final data = pushDataOf(message.data);
  final title = data['title'];
  final body = data['body'];
  if (title == null || title.isEmpty || body == null || body.isEmpty) return;

  final local = FlutterLocalNotificationsPlugin();
  await _prepareLocalNotifications(local);
  await _show(local, title: title, body: body, data: data);
}

Future<void> prepareLocalNotifications(
  FlutterLocalNotificationsPlugin local, {
  DidReceiveNotificationResponseCallback? onTap,
}) {
  return _prepareLocalNotifications(local, onTap: onTap);
}

Future<void> showPushNotification(
  FlutterLocalNotificationsPlugin local, {
  required String title,
  required String body,
  required Map<String, String> data,
}) {
  return _show(local, title: title, body: body, data: data);
}

Future<void> _prepareLocalNotifications(
  FlutterLocalNotificationsPlugin local, {
  DidReceiveNotificationResponseCallback? onTap,
}) async {
  const channel = AndroidNotificationChannel(
    pushChannelId,
    pushChannelName,
    description: pushChannelDescription,
    importance: Importance.high,
  );
  await local
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  const settings = InitializationSettings(
    android: AndroidInitializationSettings(_androidIcon),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );
  await local.initialize(settings, onDidReceiveNotificationResponse: onTap);
}

Future<void> _show(
  FlutterLocalNotificationsPlugin local, {
  required String title,
  required String body,
  required Map<String, String> data,
}) {
  final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
  return local.show(
    id,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        pushChannelId,
        pushChannelName,
        channelDescription: pushChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: _androidIcon,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    payload: encodePushPayload(data),
  );
}
