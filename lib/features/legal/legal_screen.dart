import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'legal_texts.dart';

/// Política de privacidad o términos de uso. Los textos van dentro de la app,
/// así se pueden leer sin conexión y antes de iniciar sesión.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});

  const LegalScreen.privacy({super.key}) : document = privacyPolicy;

  const LegalScreen.terms({super.key}) : document = termsOfUse;

  final LegalDocument document;

  /// Abre la pantalla sobre la actual.
  static void open(BuildContext context, LegalScreen screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5);

    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Última actualización: ${document.updated}',
            style: const TextStyle(fontSize: 12, color: AppColors.ink3),
          ),
          const SizedBox(height: 12),
          Text(document.intro, style: body),
          for (final section in document.sections) ...[
            const SizedBox(height: 20),
            Text(
              section.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
            for (final paragraph in section.paragraphs) ...[
              const SizedBox(height: 6),
              Text(paragraph, style: body),
            ],
            for (final bullet in section.bullets)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: body),
                    Expanded(child: Text(bullet, style: body)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
