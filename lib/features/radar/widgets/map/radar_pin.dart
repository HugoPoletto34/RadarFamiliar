import 'package:flutter/painting.dart';

/// Zoom ao enquadrar uma pessoa. 17 mostra cerca de um quarteirão.
const radarPersonZoom = 17.0;

/// Diâmetro do ícone em pixels de tela. Não muda com zoom nem rotação.
const radarPinSize = 44.0;

/// Marcador independente do provedor de mapa.
class RadarPin {
  const RadarPin({
    required this.id,
    required this.label,
    required this.color,
    required this.lat,
    required this.lng,
    required this.title,
    this.snippet = '',
    this.isMe = false,
  });

  final String id;
  final String label;
  final Color color;
  final double lat;
  final double lng;
  final String title;
  final String snippet;
  final bool isMe;
}

/// Comandos de câmera que a tela do mapa usa, nos dois provedores.
abstract class RadarMapHandle {
  Future<void> moveTo(double lat, double lng, {double? zoom});
  Future<void> fit(List<RadarPin> pins);
  Future<void> showInfo(String pinId);
}
