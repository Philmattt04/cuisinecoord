import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/map_provider.dart';
import 'screens/map_screen.dart';
import 'maps_initializer_stub.dart'
    if (dart.library.html) 'maps_initializer_web.dart';

void main() {
  if (kIsWeb) initializeMaps();
  runApp(
    ChangeNotifierProvider(
      create: (_) => MapProvider(),
      child: const CuisineCoordApp(),
    ),
  );
}

class CuisineCoordApp extends StatefulWidget {
  const CuisineCoordApp({super.key});

  static _CuisineCoordAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_CuisineCoordAppState>()!;

  @override
  State<CuisineCoordApp> createState() => _CuisineCoordAppState();
}

class _CuisineCoordAppState extends State<CuisineCoordApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  bool get isDark {
    if (_themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CuisineCoord',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const MapScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF1a1a2e) : const Color(0xFFF8F8F8),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF6535),
        brightness: brightness,
      ),
      useMaterial3: true,
    );
  }
}
