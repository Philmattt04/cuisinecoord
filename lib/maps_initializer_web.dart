import 'dart:async';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:google_maps_flutter_web/google_maps_flutter_web.dart';
import 'package:web/web.dart' as web;

const _placesKey = String.fromEnvironment('PLACES_KEY');

Future<void> initializeMaps() async {
  await _loadMapsScript();
  GoogleMapsPlugin.registerWith(Registrar());
}

Future<void> _loadMapsScript() {
  if (_placesKey.isEmpty) {
    // ignore: avoid_print
    print('Warning: PLACES_KEY is not set. Pass it with '
        '--dart-define=PLACES_KEY=your_key when running/building for web.');
  }
  final completer = Completer<void>();
  final script = web.HTMLScriptElement()
    ..src = 'https://maps.googleapis.com/maps/api/js?key=$_placesKey'
    ..onLoad.listen((_) => completer.complete())
    ..onError.listen((_) =>
        completer.completeError('Failed to load Google Maps JS API'));
  web.document.head!.appendChild(script);
  return completer.future;
}
