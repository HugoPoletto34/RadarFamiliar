/// Código de convite guardado até o usuário entrar (deep link antes do login).
class PendingInvite {
  PendingInvite._();

  static String? code;

  static void set(String? value) {
    final trimmed = value?.trim();
    code = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? take() {
    final value = code;
    code = null;
    return value;
  }
}
