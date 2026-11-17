import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum NoticeTone { info, success, warning, error }

/// Mensaje del sistema dentro de la pantalla. El color y el ícono dicen el
/// tipo; el texto va siempre en tinta para que se lea bien. Los errores se
/// anuncian a los lectores de pantalla de inmediato.
class Notice extends StatelessWidget {
  const Notice({super.key, this.tone = NoticeTone.info, required this.child});

  /// Atajo para el caso común: un mensaje de solo texto.
  Notice.text(String message, {super.key, this.tone = NoticeTone.info})
      : child = Text(message);

  final NoticeTone tone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (Color color, Color soft, IconData icon) = switch (tone) {
      NoticeTone.error => (
          AppColors.danger,
          AppColors.dangerSoft,
          Icons.error_outline,
        ),
      NoticeTone.success => (
          AppColors.ok,
          AppColors.okSoft,
          Icons.check_circle_outline,
        ),
      NoticeTone.warning => (
          AppColors.warn,
          AppColors.warnSoft,
          Icons.warning_amber_rounded,
        ),
      NoticeTone.info => (
          AppColors.navy,
          AppColors.navySoft,
          Icons.info_outline,
        ),
    };

    return Semantics(
      container: true,
      liveRegion: tone == NoticeTone.error,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: soft,
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DefaultTextStyle.merge(
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: AppColors.ink,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
