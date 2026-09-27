import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/application/app_controller.dart';
import 'package:adaptive_physical_communication/ui/screens/home_screen.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';
import 'package:adaptive_physical_communication/ui/widgets/optical_active_overlay.dart';

void main() {
  runApp(const AdaptiveCommApp());
}

class AdaptiveCommApp extends StatelessWidget {
  const AdaptiveCommApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppProvider(
      create: () => AppController(),
      child: MaterialApp(
        title: AppBrand.name,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3B82F6),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(centerTitle: false),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
          ),
        ),
        home: const HomeScreen(),
        builder: (context, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.shrink(),
              const OpticalActiveOverlay(),
            ],
          );
        },
      ),
    );
  }
}

class AppProvider extends StatefulWidget {
  const AppProvider({super.key, required this.create, required this.child});

  final AppController Function() create;
  final Widget child;

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_InheritedApp>();
    assert(scope != null, 'AppProvider not found');
    return scope!.controller;
  }

  @override
  State<AppProvider> createState() => _AppProviderState();
}

class _AppProviderState extends State<AppProvider> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.create();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _InheritedApp(
        controller: _controller,
        child: widget.child,
      ),
    );
  }
}

class _InheritedApp extends InheritedWidget {
  const _InheritedApp({required this.controller, required super.child});
  final AppController controller;

  @override
  bool updateShouldNotify(_InheritedApp old) => true;
}
