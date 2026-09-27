import 'package:flutter/material.dart';



import 'package:adaptive_physical_communication/core/platform/platform_capabilities.dart';



/// Responsive breakpoints: phone <600, tablet 600–1024, desktop >1024.

enum ScreenSize { phone, tablet, desktop }



class AppBreakpoints {

  static const double phone = 600;

  static const double tablet = 1024;

}



ScreenSize screenSizeOf(BuildContext context) {

  final width = MediaQuery.sizeOf(context).width;

  if (width < AppBreakpoints.phone) return ScreenSize.phone;

  if (width <= AppBreakpoints.tablet) return ScreenSize.tablet;

  return ScreenSize.desktop;

}



bool isWideLayout(BuildContext context) =>

    screenSizeOf(context) != ScreenSize.phone;



EdgeInsets pagePadding(BuildContext context) {

  final size = screenSizeOf(context);

  return EdgeInsets.all(switch (size) {

    ScreenSize.phone => 16,

    ScreenSize.tablet => 20,

    ScreenSize.desktop => 24,

  });

}



/// Consistent outer padding + max content width for desktop.

class PageContainer extends StatelessWidget {

  const PageContainer({super.key, required this.child});



  final Widget child;



  @override

  Widget build(BuildContext context) {

    return Align(

      alignment: Alignment.topCenter,

      child: ConstrainedBox(

        constraints: const BoxConstraints(maxWidth: 1400),

        child: Padding(

          padding: pagePadding(context),

          child: child,

        ),

      ),

    );

  }

}



class SectionCard extends StatelessWidget {

  const SectionCard({

    super.key,

    required this.title,

    this.subtitle,

    this.icon,

    this.trailing,

    required this.child,

  });



  final String title;

  final String? subtitle;

  final IconData? icon;

  final Widget? trailing;

  final Widget child;



  @override

  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    return Card(

      clipBehavior: Clip.antiAlias,

      child: Padding(

        padding: const EdgeInsets.all(16),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [

            Row(

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                if (icon != null) ...[

                  Icon(icon, color: theme.colorScheme.primary, size: 22),

                  const SizedBox(width: 10),

                ],

                Expanded(

                  child: Column(

                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [

                      Text(

                        title,

                        style: theme.textTheme.titleMedium?.copyWith(

                          fontWeight: FontWeight.bold,

                        ),

                      ),

                      if (subtitle != null) ...[

                        const SizedBox(height: 4),

                        Text(

                          subtitle!,

                          style: theme.textTheme.bodySmall?.copyWith(

                            color: Colors.white70,

                          ),

                        ),

                      ],

                    ],

                  ),

                ),

                ?trailing,

              ],

            ),

            const SizedBox(height: 12),

            child,

          ],

        ),

      ),

    );

  }

}



class StatusChip extends StatelessWidget {

  const StatusChip({

    super.key,

    required this.label,

    this.icon,

    this.tone = StatusTone.neutral,

  });



  final String label;

  final IconData? icon;

  final StatusTone tone;



  @override

  Widget build(BuildContext context) {

    final (bg, fg) = switch (tone) {

      StatusTone.success => (Colors.green.withValues(alpha: 0.15), Colors.greenAccent),

      StatusTone.warning => (Colors.amber.withValues(alpha: 0.15), Colors.amberAccent),

      StatusTone.error => (Colors.red.withValues(alpha: 0.15), Colors.redAccent),

      StatusTone.info => (Colors.blue.withValues(alpha: 0.15), Colors.lightBlueAccent),

      StatusTone.neutral => (Colors.white12, Colors.white70),

    };

    return Chip(

      avatar: icon != null ? Icon(icon, size: 16, color: fg) : null,

      label: Text(label, style: TextStyle(color: fg, fontSize: 12)),

      backgroundColor: bg,

      side: BorderSide(color: fg.withValues(alpha: 0.4)),

      visualDensity: VisualDensity.compact,

      padding: const EdgeInsets.symmetric(horizontal: 4),

    );

  }

}



enum StatusTone { success, warning, error, info, neutral }



class PlatformCapabilityBanner extends StatelessWidget {

  const PlatformCapabilityBanner({super.key});



  @override

  Widget build(BuildContext context) {

    final tone = isPhysicalChannelSupported

        ? (isVibrationSupported ? StatusTone.success : StatusTone.info)

        : StatusTone.warning;



    return Card(

      color: Theme.of(context).colorScheme.surfaceContainerHighest,

      child: Padding(

        padding: const EdgeInsets.all(14),

        child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Wrap(

              spacing: 8,

              runSpacing: 8,

              crossAxisAlignment: WrapCrossAlignment.center,

              children: [

                StatusChip(

                  label: platformCapabilityLabel,

                  icon: isPhysicalChannelSupported ? Icons.check_circle : Icons.info,

                  tone: tone,

                ),

                if (isPhysicalChannelSupported) ...[

                  const StatusChip(label: 'Optical', icon: Icons.flash_on, tone: StatusTone.info),

                  const StatusChip(label: 'Acoustic', icon: Icons.graphic_eq, tone: StatusTone.info),

                  if (isVibrationSupported)

                    const StatusChip(label: 'Vibration', icon: Icons.vibration, tone: StatusTone.info),

                ],

                const StatusChip(
                  label: 'No internet',
                  icon: Icons.wifi_off,
                  tone: StatusTone.neutral,
                ),

              ],

            ),

            const SizedBox(height: 10),

            Text(

              platformCapabilitySummary,

              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),

            ),

          ],

        ),

      ),

    );

  }

}



class EmptyState extends StatelessWidget {

  const EmptyState({

    super.key,

    required this.icon,

    required this.message,

    this.subtitle,

  });



  final IconData icon;

  final String message;

  final String? subtitle;



  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 130;
        final iconSize = compact ? 24.0 : 36.0;
        final pad = compact ? 8.0 : 16.0;

        return Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: iconSize, color: Colors.white24),
                  SizedBox(height: compact ? 6 : 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: compact ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white54,
                          fontSize: compact ? 12 : 14,
                        ),
                  ),
                  if (subtitle != null && !compact) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

}



class PairingInstructionsCard extends StatelessWidget {

  const PairingInstructionsCard({super.key});



  @override

  Widget build(BuildContext context) {

    return SectionCard(

      title: 'Broadcast & Pairing',

      subtitle: 'One sender can reach many receivers',

      icon: Icons.devices,

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          for (var i = 0; i < hardwarePairingSteps.length; i++)

            Padding(

              padding: const EdgeInsets.only(bottom: 6),

              child: Row(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  SizedBox(

                    width: 22,

                    child: Text(

                      '${i + 1}.',

                      style: const TextStyle(

                        color: Colors.white54,

                        fontWeight: FontWeight.bold,

                      ),

                    ),

                  ),

                  Expanded(child: Text(hardwarePairingSteps[i])),

                ],

              ),

            ),

        ],

      ),

    );

  }

}

