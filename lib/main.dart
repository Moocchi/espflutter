import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const GanciApp(),
    ),
  );
}

class GanciApp extends StatelessWidget {
  const GanciApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'image2cpp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6252E7),
          secondary: Color(0xFF6252E7),
          surface: Color(0xFF0E1E2E),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A1520),
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF6252E7),
          thumbColor: Color(0xFF6252E7),
          inactiveTrackColor: Color(0xFF1A3048),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected))
              return const Color(0xFF6252E7);
            return Colors.transparent;
          }),
        ),
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected))
              return const Color(0xFF6252E7);
            return Colors.white38;
          }),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected))
              return const Color(0xFF6252E7);
            return Colors.white38;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected))
              return const Color(0xFF6252E7).withOpacity(0.4);
            return Colors.white12;
          }),
        ),
        textTheme: const TextTheme(
          bodyMedium:
              TextStyle(fontFamily: 'sans-serif', color: Colors.white70),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1A2E40),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

