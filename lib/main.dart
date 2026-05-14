import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/map_provider.dart';
import 'screens/map_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => MapProvider(),
      child: const CuisineCoordApp(),
    ),
  );
}

class CuisineCoordApp extends StatelessWidget {
  const CuisineCoordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CuisineCoord',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1a1a2e),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6535),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
