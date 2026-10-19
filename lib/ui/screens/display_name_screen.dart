import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:adaptive_physical_communication/core/user/user_profile_store.dart';
import 'package:adaptive_physical_communication/main.dart';
import 'package:adaptive_physical_communication/ui/theme/app_layout.dart';
import 'package:adaptive_physical_communication/ui/widgets/app_logo.dart';

/// First-launch (or change-name) screen for a short display name.
class DisplayNameScreen extends StatefulWidget {
  const DisplayNameScreen({
    super.key,
    this.initialName,
    this.allowSkip = false,
  });

  final String? initialName;
  final bool allowSkip;

  @override
  State<DisplayNameScreen> createState() => _DisplayNameScreenState();
}

class _DisplayNameScreenState extends State<DisplayNameScreen> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cleaned = UserProfileStore.sanitize(_controller.text);
    if (cleaned == null) {
      setState(() => _error = 'Enter a short name (1–${UserProfileStore.maxNameLength} characters)');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final app = AppProvider.of(context);
    final ok = await app.setDisplayName(cleaned);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _saving = false;
        _error = 'Could not save your name. Try again.';
      });
      return;
    }

    if (widget.allowSkip && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining =
        UserProfileStore.maxNameLength - _controller.text.trim().length;

    return Scaffold(
      body: SafeArea(
        child: PageContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 28),
              const Center(child: AppLogo(size: 72)),
              const SizedBox(height: 28),
              Text(
                'What should we call you?',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your short name is sent with each message so the other phone '
                'can show who it came from. Keep it brief to stay fast.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.words,
                maxLength: UserProfileStore.maxNameLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1f\x7f]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Display name',
                  hintText: 'e.g. Harsh',
                  errorText: _error,
                  counterText: remaining >= 0 ? '$remaining left' : null,
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? 'Saving…' : 'Continue'),
              ),
              if (widget.allowSkip) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
