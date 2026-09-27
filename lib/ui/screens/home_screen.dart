import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';
import 'package:adaptive_physical_communication/ui/screens/dev_menu_screen.dart';
import 'package:adaptive_physical_communication/ui/screens/receive_screen.dart';
import 'package:adaptive_physical_communication/ui/screens/send_compose_screen.dart';
import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';

/// Landing screen — app name plus Send and Receive actions.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const appName = AppBrand.name;
  static const appTagline = AppBrand.tagline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      body: SafeArea(
        child: PageContainer(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'About',
                        onPressed: () => showAppAboutDialog(context),
                        icon: Icon(Icons.info_outline, color: Colors.white.withValues(alpha: 0.5)),
                      ),
                      IconButton(
                        tooltip: 'Developer tools',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const DevMenuScreen()),
                        ),
                        icon: Icon(Icons.more_vert, color: Colors.white.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                  SizedBox(height: size.height * 0.05),
                  AppLogo(size: (size.width * 0.3).clamp(96.0, 148.0)),
                  const SizedBox(height: 28),
                  Text(
                    appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appTagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      physicalOnlyPolicySummary,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white38,
                        height: 1.45,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(height: size.height * 0.06),
                  _ActionButton(
                    icon: Icons.send_rounded,
                    label: 'Send',
                    subtitle: 'Compose and transmit a message',
                    color: theme.colorScheme.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SendComposeScreen()),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ActionButton(
                    icon: Icons.download_rounded,
                    label: 'Receive',
                    subtitle: 'Listen for incoming messages',
                    color: Colors.tealAccent,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReceiveScreen()),
                    ),
                  ),
                  SizedBox(height: size.height * 0.04),
                  Text(
                    platformCapabilityLabel,
                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.white30),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withValues(alpha: 0.2),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 18, color: color.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
