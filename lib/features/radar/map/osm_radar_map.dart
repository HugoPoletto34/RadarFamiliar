import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'radar_pin.dart';

/// Mapa usado quando não há chave do Google Maps (protótipo local): tiles do
/// OpenStreetMap (só uso leve de desenvolvimento) em cinza claro, para o mapa
/// não competir com os marcadores.
class OsmRadarMap extends StatefulWidget {
  const OsmRadarMap({
    super.key,
    required this.pins,
    required this.initialLat,
    required this.initialLng,
    required this.onReady,
  });

  final List<RadarPin> pins;
  final double initialLat;
  final double initialLng;
  final ValueChanged<RadarMapHandle> onReady;

  @override
  State<OsmRadarMap> createState() => _OsmRadarMapState();
}

class _OsmRadarMapState extends State<OsmRadarMap> implements RadarMapHandle {
  final _map = MapController();
  String? _selected;

  @override
  Future<void> moveTo(double lat, double lng, {double? zoom}) async {
    _map.move(LatLng(lat, lng), zoom ?? _map.camera.zoom);
  }

  @override
  Future<void> fit(List<RadarPin> pins) async {
    if (pins.isEmpty) return;
    if (pins.length == 1) {
      return moveTo(pins.first.lat, pins.first.lng, zoom: 15);
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          for (final p in pins) LatLng(p.lat, p.lng),
        ]),
        padding: const EdgeInsets.all(80),
      ),
    );
  }

  @override
  Future<void> showInfo(String pinId) async =>
      setState(() => _selected = pinId);

  @override
  Widget build(BuildContext context) {
    final pins = [...widget.pins]
      ..sort((a, b) => (a.isMe ? 1 : 0) - (b.isMe ? 1 : 0));
    final selected = pins.where((p) => p.id == _selected).firstOrNull;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: LatLng(widget.initialLat, widget.initialLng),
        initialZoom: 14,
        onMapReady: () => widget.onReady(this),
        onTap: (_, _) => setState(() => _selected = null),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'br.com.radarfamiliar',
          tileBuilder: (context, tile, _) =>
              ColorFiltered(colorFilter: _minimalFilter, child: tile),
        ),
        MarkerLayer(
          markers: [
            for (final p in pins)
              Marker(
                point: LatLng(p.lat, p.lng),
                width: 44,
                height: 44,
                child: GestureDetector(
                  onTap: () => setState(() => _selected = p.id),
                  child: _PinBubble(pin: p),
                ),
              ),
          ],
        ),
        if (selected != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(selected.lat, selected.lng),
                width: 220,
                height: 110,
                alignment: Alignment.topCenter,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            selected.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (selected.snippet.isNotEmpty)
                            Text(
                              selected.snippet,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
        ),
      ],
    );
  }
}

/// Tons de cinza misturados 45% com branco: tira as cores e apaga os textos.
const _minimalFilter = ColorFilter.matrix([
  0.55 * 0.2126, 0.55 * 0.7152, 0.55 * 0.0722, 0, 115, //
  0.55 * 0.2126, 0.55 * 0.7152, 0.55 * 0.0722, 0, 115, //
  0.55 * 0.2126, 0.55 * 0.7152, 0.55 * 0.0722, 0, 115, //
  0, 0, 0, 1, 0,
]);

class _PinBubble extends StatelessWidget {
  const _PinBubble({required this.pin});

  final RadarPin pin;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: pin.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Center(
        child: Text(
          pin.label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: pin.label.length > 1 ? 13 : 18,
          ),
        ),
      ),
    );
  }
}
