import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'radar_pin.dart';

/// Google Maps sem Map ID. Exige GOOGLE_MAPS_API_KEY em `env/<flavor>.json`.
class GoogleRadarMap extends StatefulWidget {
  const GoogleRadarMap({
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
  State<GoogleRadarMap> createState() => _GoogleRadarMapState();
}

class _GoogleRadarMapState extends State<GoogleRadarMap>
    implements RadarMapHandle {
  GoogleMapController? _map;
  final _icons = <String, BitmapDescriptor>{};
  String? _style;

  @override
  void didUpdateWidget(GoogleRadarMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_prepareIcons());
  }

  @override
  void initState() {
    super.initState();
    unawaited(_prepareIcons());
    unawaited(
      rootBundle.loadString('assets/map_style.json').then((s) {
        if (mounted) setState(() => _style = s);
      }),
    );
  }

  String _key(RadarPin p) => '${p.label}|${p.color.toARGB32()}';

  Future<void> _prepareIcons() async {
    var created = false;
    for (final p in widget.pins) {
      final key = _key(p);
      if (!_icons.containsKey(key)) {
        _icons[key] = await _draw(p.label, p.color);
        created = true;
      }
    }
    if (created && mounted) setState(() {});
  }

  @override
  Future<void> moveTo(double lat, double lng, {double? zoom}) async {
    await _map?.animateCamera(
      zoom == null
          ? CameraUpdate.newLatLng(LatLng(lat, lng))
          : CameraUpdate.newLatLngZoom(LatLng(lat, lng), zoom),
    );
  }

  @override
  Future<void> fit(List<RadarPin> pins) async {
    if (pins.isEmpty) return;
    if (pins.length == 1) {
      return moveTo(pins.first.lat, pins.first.lng, zoom: 15);
    }
    final lats = pins.map((p) => p.lat);
    final lngs = pins.map((p) => p.lng);
    await _map?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(lats.reduce(_min), lngs.reduce(_min)),
          northeast: LatLng(lats.reduce(_max), lngs.reduce(_max)),
        ),
        80,
      ),
    );
  }

  @override
  Future<void> showInfo(String pinId) async =>
      _map?.showMarkerInfoWindow(MarkerId(pinId));

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.initialLat, widget.initialLng),
        zoom: 14,
      ),
      style: _style,
      buildingsEnabled: false,
      indoorViewEnabled: false,
      trafficEnabled: false,
      compassEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: (m) {
        _map = m;
        widget.onReady(this);
      },
      markers: {
        for (final p in widget.pins)
          if (_icons[_key(p)] case final icon?)
            Marker(
              markerId: MarkerId(p.id),
              position: LatLng(p.lat, p.lng),
              icon: icon,
              anchor: const Offset(0.5, 0.5),
              zIndexInt: p.isMe ? 2 : 1,
              infoWindow: InfoWindow(title: p.title, snippet: p.snippet),
            ),
      },
    );
  }

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;

  /// Círculo com borda branca e a inicial (ou "Eu") no centro.
  static Future<BitmapDescriptor> _draw(String label, Color color) async {
    const size = 120.0;
    const r = size / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(r, r + 3),
      r - 4,
      Paint()..color = Colors.black26,
    );
    canvas.drawCircle(const Offset(r, r), r - 4, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(r, r), r - 14, Paint()..color = color);
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: label.length > 1 ? 38 : 50,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(r - text.width / 2, r - text.height / 2));
    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(png!.buffer.asUint8List(), width: 44);
  }
}
