import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_session.dart';
import '../state/ecoscan_store.dart';
import 'app_image.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({this.radius = 25, this.onTap, super.key});
  final double radius;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSession>();
    final user = auth.account;
    final local = context.watch<EcoScanStore>().profilePhoto;
    final name = auth.isGuest
        ? 'Visitante'
        : user?.name.isNotEmpty == true
        ? user!.name
        : user?.email ?? 'U';
    final fallback = Center(
      child: Text(
        name.substring(0, 1).toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: radius * 0.65),
      ),
    );
    return Semantics(
      label: 'Foto do perfil',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: CircleAvatar(
          radius: radius,
          child: ClipOval(
            child: SizedBox.square(
              dimension: radius * 2,
              child: local.isNotEmpty
                  ? AppImage(
                      source: local,
                      fit: BoxFit.cover,
                      fallback: fallback,
                    )
                  : fallback,
            ),
          ),
        ),
      ),
    );
  }
}
