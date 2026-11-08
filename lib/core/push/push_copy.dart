import 'dart:convert';

/// Texto exibido no push. A Edge Function `send-push` repete estas frases:
/// se mudar aqui, mude lá também.
class PushText {
  const PushText({required this.title, required this.body});

  final String title;
  final String body;
}

PushText pushText(String type, Map<String, String> payload) {
  final member = _clean(payload['member_name']);
  final watcher = _clean(payload['watcher_name']);
  final place = _clean(payload['place_name']);

  switch (type) {
    case 'member_joined':
      return PushText(
        title: 'Novo integrante',
        body: member == null
            ? 'Alguém entrou no grupo'
            : '$member entrou no grupo',
      );
    case 'alert_created_about_you':
      return PushText(
        title: 'Alerta sobre você',
        body: _alertBody(watcher, place),
      );
    default:
      return PushText(
        title: _clean(payload['title']) ?? 'Radar Familiar',
        body: _clean(payload['body']) ?? 'Você tem uma nova notificação',
      );
  }
}

String _alertBody(String? watcher, String? place) {
  if (watcher != null && place != null) {
    return '$watcher criou um alerta em $place';
  }
  if (watcher != null) return '$watcher criou um alerta sobre você';
  if (place != null) return 'Criaram um alerta sobre você em $place';
  return 'Criaram um alerta sobre você';
}

String? _clean(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty || text == 'null') return null;
  return text;
}

Map<String, String> pushDataOf(Map<String, dynamic> data) {
  return data.map((key, value) => MapEntry(key, value?.toString() ?? ''));
}

Map<String, String>? decodePushPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    return Map<Object?, Object?>.from(decoded).map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  } on Object {
    return null;
  }
}

String encodePushPayload(Map<String, String> data) => jsonEncode(data);
