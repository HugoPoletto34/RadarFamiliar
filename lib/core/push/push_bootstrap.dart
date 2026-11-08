import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_notifications.dart';

/// O Firebase é usado só para o FCM. Enquanto `google-services.json` /
/// `GoogleService-Info.plist` não existirem, o app segue sem push.
Future<bool> initPush() async {
  if (!Platform.isAndroid && !Platform.isIOS) return false;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    return true;
  } on Object catch (e) {
    debugPrint('Firebase não configurado, push desativado: $e');
    return false;
  }
}
