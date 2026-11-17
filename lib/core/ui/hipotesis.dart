import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'badges.dart';
import 'notice.dart';

/// Contenido de una hipótesis generada por la IA, igual que en la web
/// (`Hipotesis.tsx`). Se usa en el resultado del escaneo, en el detalle del
/// historial y en el detalle de la orden, para que diga lo mismo en todos.
///
/// Recibe el `Diagnosis` tal como lo devuelve el backend: `summary` y
/// `recommendations` con `probableCauses`, `verificationSteps` y
/// `correlations`.
class HipotesisView extends StatelessWidget {
  const HipotesisView({super.key, required this.diagnosis});

  final Map<String, dynamic> diagnosis;

  @override
  Widget build(BuildContext context) {
    final summary = (diagnosis['summary'] as String?)?.trim() ?? '';
    final rec = diagnosis['recommendations'];
    final recommendations =
        rec is Map<String, dynamic> ? rec : const <String, dynamic>{};
    final causes =
        (recommendations['probableCauses'] as List<dynamic>?) ?? const [];
    final steps =
        (recommendations['verificationSteps'] as List<dynamic>?) ?? const [];
    final correlations =
        (recommendations['correlations'] as String?)?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // La validación humana es el eje del sistema: va antes del contenido.
        Notice(
          tone: NoticeTone.warning,
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Requiere validación de un profesional. ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const TextSpan(
                  text:
                      'Son hipótesis por verificar, no un diagnóstico confirmado.',
                ),
              ],
            ),
          ),
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(summary, style: const TextStyle(fontSize: 14, height: 1.4)),
        ],
        if (causes.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _Subtitulo('Causas probables'),
          for (final raw in causes)
            if (raw is Map<String, dynamic>)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${raw['cause'] ?? ''}',
                        style: const TextStyle(fontSize: 14, height: 1.35),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConfidenceBadge(raw['confidence'] as String?),
                  ],
                ),
              ),
        ],
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _Subtitulo('Pasos de verificación'),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}.',
                      style: AppText.nums.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${steps[i]}',
                      style: const TextStyle(fontSize: 14, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Van del más barato y menos invasivo al más costoso.',
            style: TextStyle(fontSize: 12, color: AppColors.ink3),
          ),
        ],
        if (correlations.isNotEmpty) ...[
          const SizedBox(height: 16),
          const _Subtitulo('Relación entre los códigos'),
          Text(correlations,
              style: const TextStyle(fontSize: 14, height: 1.35)),
        ],
      ],
    );
  }
}

class _Subtitulo extends StatelessWidget {
  const _Subtitulo(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}
