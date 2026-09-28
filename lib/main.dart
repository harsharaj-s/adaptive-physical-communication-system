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
          colorScheme:
              ColorScheme.fromSeed(
                seedColor: const Color(0xFF6EA8FE),
                brightness: Brightness.dark,
              ).copyWith(
                primary: const Color(0xFF76A9FF),
                secondary: const Color(0xFF55E3C2),
                surface: const Color(0xFF111C2E),
                surfaceContainer: const Color(0xFF16243A),
                surfaceContainerHighest: const Color(0xFF1B2B44),
              ),
          useMaterial3: true,
          fontFamily: 'Roboto',
          scaffoldBackgroundColor: const Color(0xFF091423),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          textTheme: Typography.material2021().white.apply(
            bodyColor: const Color(0xFFF3F7FF),
            displayColor: const Color(0xFFF3F7FF),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              side: const BorderSide(color: Color(0xFF456182)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: const Color(0xFF111F33),
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFF223755)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            hintStyle: const TextStyle(color: Color(0xFF98A9C1)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF2A4264)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF76A9FF), width: 2),
            ),
            filled: true,
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Color(0xFF111F33),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF203653),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
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
      builder: (context, _) =>
          _InheritedApp(controller: _controller, child: widget.child),
    );
  }
}

class _InheritedApp extends InheritedWidget {
  const _InheritedApp({required this.controller, required super.child});
  final AppController controller;

  @override
  bool updateShouldNotify(_InheritedApp old) => true;
}
