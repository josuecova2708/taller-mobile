import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_service.dart';
import '../../core/api/api_client.dart';
import '../../core/push/push_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/badges.dart';
import '../legal/legal_screen.dart';

/// Muestra la identidad y los permisos efectivos de la sesión, y permite salir.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final permissions = auth.permissions;
    final initial = auth.userName.isNotEmpty ? auth.userName[0].toUpperCase() : '-';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuenta'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.navySoft,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.userName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (auth.user?['email'] as String?) ?? '',
                          style: const TextStyle(fontSize: 13, color: AppColors.ink2),
                        ),
                        if ((auth.user?['unit'] as Map<String, dynamic>?)?['name']
                            case final String facultad) ...[
                          const SizedBox(height: 2),
                          Text(
                            facultad,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.ink2),
                          ),
                        ],
                        const SizedBox(height: 8),
                        StatusBadge(auth.roleLabel, tone: BadgeTone.brand),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('Notificaciones'),
          const SizedBox(height: 8),
          _NotificationsCard(
              push: auth.push, receivesAlerts: auth.can('order:update_status')),
          const SizedBox(height: 16),
          const _SectionLabel('Permisos de su rol'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: permissions
                  .map(
                    (permission) => ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.check,
                        size: 18,
                        color: AppColors.navy,
                      ),
                      title: Text(
                        permission,
                        style: AppText.code.copyWith(fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Política de privacidad'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      LegalScreen.open(context, const LegalScreen.privacy()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Términos de uso'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => LegalScreen.open(context, const LegalScreen.terms()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
          const SizedBox(height: 16),
          const _ServerLine(),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthService>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          'Se borrará la sesión de este dispositivo. Deberá iniciar sesión nuevamente para enviar escaneos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await auth.logout();
    }
  }
}

/// Estado de las notificaciones push en este teléfono y botón de prueba.
class _NotificationsCard extends StatefulWidget {
  const _NotificationsCard({required this.push, required this.receivesAlerts});

  final PushService push;

  /// Solo quienes atienden órdenes (mecánico y administrador) reciben el aviso
  /// de una orden nueva. El inspector recibe los de los vehículos de los que
  /// es responsable.
  final bool receivesAlerts;

  @override
  State<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<_NotificationsCard> {
  bool _sending = false;

  Future<void> _sendTest() async {
    setState(() => _sending = true);
    final message = await widget.push.sendTest();
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ValueListenableBuilder<PushStatus>(
        valueListenable: widget.push.status,
        builder: (context, status, _) {
          final active = status == PushStatus.activo;
          final text = active && !widget.receivesAlerts
              ? 'Notificaciones activas. Le llegan los avisos de los vehículos '
                  'de los que es responsable; los de órdenes nuevas van a '
                  'mecánicos y administradores.'
              : PushService.describe(status);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      active
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      color: active ? AppColors.ok : AppColors.inkOff,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(fontSize: 14, height: 1.35),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _sending ? null : _sendTest,
                  child: Text(_sending ? 'Enviando…' : 'Enviar notificación de prueba'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Rótulo de una sección de la pantalla.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.ink2,
      ),
    );
  }
}

/// Servidor al que está conectada la app. Solo se muestra cuando no es el de
/// la universidad, para que un teléfono de pruebas no pase por uno real.
class _ServerLine extends StatelessWidget {
  const _ServerLine();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: ApiClient().getBaseUrl(),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url == ApiClient.productionBaseUrl) {
          return const SizedBox.shrink();
        }
        return Text(
          'Conectado a un servidor de pruebas:\n$url',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.ink3),
        );
      },
    );
  }
}
