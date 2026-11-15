import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_service.dart';
import '../../core/push/push_service.dart';
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
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
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
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
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
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (auth.user?['email'] as String?) ?? '',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 6),
                        Chip(
                          label: Text(auth.roleLabel),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Colors.blue.shade50,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'NOTIFICACIONES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          _NotificationsCard(push: auth.push, receivesAlerts: auth.can('order:read')),
          const SizedBox(height: 16),
          Text(
            'PERMISOS EFECTIVOS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: permissions
                  .map(
                    (permission) => ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: Colors.green,
                      ),
                      title: Text(
                        permission,
                        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
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
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
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

  /// Solo quienes pueden ver órdenes reciben el aviso de una orden nueva.
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
              ? 'Notificaciones activas. Los avisos de órdenes de trabajo '
                  'llegan a mecánicos y administradores.'
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
                      color: active ? Colors.green.shade700 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text)),
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
