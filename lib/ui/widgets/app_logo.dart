import 'package:flutter/material.dart';

/// App name, tagline and logo shared by every branded surface.
abstract final class AppBrand {
  static const name = 'Adaptive Physical Communication';
  static const shortName = 'Adaptive Comm';
  static const tagline = 'Send messages without internet';
  static const version = '1.0.0';

  /// Rounded launcher tile (dark background). Drawn by `tool/make_app_icon.py`.
  static const iconAsset = 'assets/branding/app_icon.png';

  /// Transparent mark only; its centre is white, so use it on dark surfaces.
  static const markAsset = 'assets/branding/app_mark.png';
}

/// The app logo, either the full launcher tile or the bare mark.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48, this.markOnly = false});

  final double size;
  final bool markOnly;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      markOnly ? AppBrand.markAsset : AppBrand.iconAsset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: '${AppBrand.name} logo',
    );
  }
}

/// AppBar title with the logo mark in front of [title].
class BrandedTitle extends StatelessWidget {
  const BrandedTitle(this.title, {super.key, this.subtitle});

  final String title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Text(title, overflow: TextOverflow.ellipsis);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppLogo(size: 34, markOnly: true),
        const SizedBox(width: 8),
        Flexible(
          child: subtitle == null
              ? text
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DefaultTextStyle.merge(style: const TextStyle(fontSize: 18), child: text),
                    subtitle!,
                  ],
                ),
        ),
      ],
    );
  }
}

/// Standard About dialog (with licences page) carrying the logo.
void showAppAboutDialog(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: AppBrand.name,
    applicationVersion: AppBrand.version,
    applicationIcon: const AppLogo(size: 56),
    children: const [
      SizedBox(height: 12),
      Text(
        'Phone-to-phone messages, photos and videos over light (fountain QR), '
        'sound (multi-tone FSK) and vibration, with no network at all.',
      ),
    ],
  );
}
