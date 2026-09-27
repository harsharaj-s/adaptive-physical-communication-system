import 'package:flutter/material.dart';

import 'package:adaptive_physical_communication/ui/screens/hardware_screen.dart';
import 'package:adaptive_physical_communication/ui/screens/performance_screen.dart';
import 'package:adaptive_physical_communication/ui/screens/simulation_screen.dart';
import 'package:adaptive_physical_communication/ui/screens/transfer_screen.dart';
import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';

/// Hidden developer menu for simulation, hardware lab, and legacy screens.
class DevMenuScreen extends StatelessWidget {
  const DevMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const BrandedTitle('Developer tools')),
      body: PageContainer(
        child: ListView(
          children: [
            Text(
              'These tools are for development and testing. The main app uses Send / Receive on the home screen.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 16),
            _DevTile(
              icon: Icons.memory,
              title: 'Simulation Lab',
              subtitle: 'Virtual endpoints with adaptive channel switching',
              onTap: () => _push(context, const SimulationScreen()),
            ),
            _DevTile(
              icon: Icons.devices,
              title: 'Hardware Channels',
              subtitle: 'Test optical, acoustic, and vibration directly',
              onTap: () => _push(context, const HardwareScreen()),
            ),
            _DevTile(
              icon: Icons.swap_horiz,
              title: 'Legacy Messages',
              subtitle: 'Original transfer screen with logs and pairing',
              onTap: () => _push(context, const TransferScreen()),
            ),
            _DevTile(
              icon: Icons.bar_chart,
              title: 'Performance Comparison',
              subtitle: 'Compare fixed vs adaptive strategies',
              onTap: () => _push(context, const PerformanceScreen()),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const AppLogo(size: 40),
                title: const Text('About', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  '${AppBrand.name} ${AppBrand.version} · licences',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAppAboutDialog(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _DevTile extends StatelessWidget {
  const _DevTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
