import 'package:flutter/material.dart';

class GoogleSignInAction extends StatelessWidget {
  const GoogleSignInAction({
    required this.busy,
    required this.ready,
    required this.onPressed,
    super.key,
  });

  final bool busy;
  final bool ready;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const SizedBox(
        height: 44,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: const Text(
        'G',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      label: const Text('Continuar com Google'),
    );
  }
}
