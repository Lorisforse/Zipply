import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ziply_app/constants.dart';

/// TileLayer condiviso di Ziply: tile scure di Stadia Maps (tema
/// alidade_smooth_dark) con la chiave da [kStadiaApiKey] e lo User-Agent
/// dell'app. Centralizzato qui per non duplicare la configurazione tra la
/// mappa e la schermata di noleggio: si cambia in un punto solo.
TileLayer ziplyTileLayer(BuildContext context) {
  return TileLayer(
    urlTemplate:
        'https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png?api_key=$kStadiaApiKey',
    retinaMode: RetinaMode.isHighDensity(context),
    userAgentPackageName: 'it.lorisamato.ziply',
  );
}
