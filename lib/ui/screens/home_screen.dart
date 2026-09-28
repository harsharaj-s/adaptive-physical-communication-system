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
    return Scaffold(
      body: SafeArea(
        child: PageContainer(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainer.withValues(
                            alpha: 0.75,
                          ),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          'OFFLINE READY',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'About Adaptive Comm',
                            onPressed: () => showAppAboutDialog(context),
                            icon: const Icon(Icons.info_outline),
                          ),
                          IconButton(
                            tooltip: 'Developer tools',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DevMenuScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.more_horiz),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 34),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                      child: const AppLogo(size: 96),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    appTagline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      physicalOnlyPolicySummary,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.8,
                        ),
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 38),
                  _ActionButton(
                    icon: Icons.send_rounded,
                    label: 'Send',
                    subtitle:
                        'Write a message, add media, then choose a signal',
                    color: theme.colorScheme.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SendComposeScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ActionButton(
                    icon: Icons.sensors_rounded,
                    label: 'Receive',
                    subtitle: 'Listen or scan for an incoming signal',
                    color: theme.colorScheme.secondary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReceiveScreen()),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer.withValues(
                        alpha: 0.7,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            platformCapabilityLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: color.withValues(alpha: 0.16),
                child: Icon(icon, color: color, size: 27),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
