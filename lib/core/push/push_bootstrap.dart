import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// O Firebase é usado só para o FCM. Enquanto `google-services.json` /
/// `GoogleService-Info.plist` não existirem, o app segue sem push.
Future<bool> initPush() async {
  try {
    await Firebase.initializeApp();
    return true;
  } on Object catch (e) {
    debugPrint('Firebase não configurado, push desativado: $e');
    return false;
  }
}
