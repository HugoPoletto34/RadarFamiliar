import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_copy.dart';
import 'push_notifications.dart';

/// Abertura vinda de um toque na notificação.
class PushOpen {
  const PushOpen(this.data);

  final Map<String, String> data;

  String? get groupId {
    final id = data['group_id'];
    if (id == null || id.isEmpty) return null;
    return id;
  }
}

/// Permissão, token FCM e exibição com o app aberto.
/// O envio em si sai da fila `notifications_outbox` pela Edge Function.
class PushService {
  PushService(this._client, {FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final SupabaseClient _client;
  final FirebaseMessaging _messaging;
  final _local = FlutterLocalNotificationsPlugin();
  final _opens = StreamController<PushOpen>.broadcast();

  PushOpen? _pending;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<AuthState>? _authSub;
  bool _started = false;

  Stream<PushOpen> get opens => _opens.stream;

  PushOpen? takePending() {
    final pending = _pending;
    _pending = null;
    return pending;
  }

  Future<void> start() async {
    if (_started || (!Platform.isAndroid && !Platform.isIOS)) return;
    _started = true;

    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
    await prepareLocalNotifications(
      _local,
      onTap: (response) {
        final data = decodePushPayload(response.payload);
        if (data != null) _open(data);
      },
    );

    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final data = decodePushPayload(launch?.notificationResponse?.payload);
      if (data != null) _open(data);
    }

    FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showForeground(message));
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _open(pushDataOf(message.data));
    });

    final initial = await _messaging.getInitialMessage();
    if (initial != null) _open(pushDataOf(initial.data));

    _tokenSub = _messaging.onTokenRefresh.listen((token) {
      unawaited(_register(token));
    });
    _authSub = _client.auth.onAuthStateChange.listen((state) {
      if (state.session != null) unawaited(syncToken());
    });
    await syncToken();
  }

  Future<void> syncToken() async {
    if (_client.auth.currentSession == null) return;
    final token = await _token();
    if (token == null) return;
    await _register(token);
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final data = pushDataOf(message.data);
    final title = message.notification?.title ?? data['title'];
    final body = message.notification?.body ?? data['body'];
    if (title == null || title.isEmpty || body == null || body.isEmpty) {
      return;
    }
    data['title'] = title;
    data['body'] = body;
    await showPushNotification(
      _local,
      title: title,
      body: body,
      data: data,
    );
  }

  Future<String?> _token() async {
    try {
      if (Platform.isIOS) {
        final apns = await _messaging.getAPNSToken();
        if (apns == null) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
      return _messaging.getToken();
    } on Object catch (e) {
      debugPrint('Token FCM indisponível: $e');
      return null;
    }
  }

  Future<void> _register(String token) async {
    if (_client.auth.currentSession == null) return;
    try {
      await _client.rpc<String>(
        'register_device',
        params: {
          'p_platform': Platform.isIOS ? 'ios' : 'android',
          'p_fcm_token': token,
        },
      );
    } on Object catch (e) {
      debugPrint('Não foi possível registrar o aparelho: $e');
    }
  }

  void _open(Map<String, String> data) {
    if (data['type'] == null || data['type']!.isEmpty) return;
    final open = PushOpen(data);
    if (_opens.hasListener) {
      _opens.add(open);
    } else {
      _pending = open;
    }
  }
}
