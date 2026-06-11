import 'package:flutter/material.dart';

// [MOBILE] Schermata mappa con flutter_map e OpenStreetMap.
// Mostra i veicoli disponibili nelle vicinanze tramite latlong2 e geolocator.
// TODO: implementare la mappa interattiva con marker veicoli.
class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1A1A1A),
      body: Center(child: Text('Mappa — coming soon')),
    );
  }
}
