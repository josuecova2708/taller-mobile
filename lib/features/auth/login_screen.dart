import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/notice.dart';
import '../../core/ui/panel.dart';
import '../legal/legal_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController();
  final ApiClient _apiClient = ApiClient();

  bool _obscurePassword = true;
  bool _showServerConfig = false;
  String? _error;

  /// El servidor desplegado se apaga cuando no tiene uso; si la respuesta
  /// demora, se avisa que está arrancando en vez de dejar solo el botón girando.
  bool _slow = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _apiClient.getBaseUrl().then((url) {
      if (!mounted) return;
      _serverController.text = url;
      // Si el teléfono quedó apuntando a otro servidor, que se vea.
      if (url != ApiClient.defaultBaseUrl) {
        setState(() => _showServerConfig = true);
      }
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Se resuelve antes del primer await para no usar el BuildContext después.
    final auth = context.read<AuthService>();

    setState(() {
      _error = null;
      _slow = false;
    });
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _slow = true);
    });

    // El servidor solo se toca si la sección está abierta: lo normal es usar
    // el que trae la app.
    if (_showServerConfig) {
      await _apiClient.setBaseUrl(_serverController.text);
    }

    final ok = await auth.login(
      _emailController.text,
      _passwordController.text,
    );

    _slowTimer?.cancel();
    if (!ok && mounted) {
      setState(() {
        _slow = false;
        _error = auth.error ?? 'No se pudo iniciar sesión. Intente de nuevo.';
      });
    }
  }

  void _resetServer() {
    setState(() => _serverController.text = ApiClient.defaultBaseUrl);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    const small = TextStyle(fontSize: 12, color: AppColors.ink3);

    return Scaffold(
      // Fondo blanco puro: el escudo viene sobre blanco y así no se ve su caja.
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const BrandStripe(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Image.asset(
                              'assets/images/uagrm.jpg',
                              width: 112,
                              height: 109,
                              semanticLabel:
                                  'Escudo de la Universidad Autónoma Gabriel René Moreno',
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Diagnóstico vehicular preventivo',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                              height: 1.2,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Parque automotor de la Universidad Autónoma '
                            'Gabriel René Moreno',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: AppColors.ink2),
                          ),
                          const SizedBox(height: 32),

                          if (_error != null) ...[
                            Notice.text(_error!, tone: NoticeTone.error),
                            const SizedBox(height: 16),
                          ] else if (_slow && auth.loading) ...[
                            Notice.text(
                              'El servidor se está iniciando. La primera '
                              'conexión puede tardar hasta un minuto.',
                            ),
                            const SizedBox(height: 16),
                          ],

                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Ingrese su correo';
                              }
                              if (!value.contains('@')) {
                                return 'El correo debe incluir una @';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Mostrar contraseña'
                                    : 'Ocultar contraseña',
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: AppColors.ink3,
                                ),
                                onPressed: () {
                                  setState(() => _obscurePassword = !_obscurePassword);
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Ingrese su contraseña';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 20),

                          FilledButton(
                            onPressed: auth.loading ? null : _submit,
                            child: Text(
                              auth.loading ? 'Iniciando sesión…' : 'Iniciar sesión',
                            ),
                          ),
                          const SizedBox(height: 24),

                          const Text(
                            'Las cuentas las crea el administrador del sistema.',
                            textAlign: TextAlign.center,
                            style: small,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Al iniciar sesión acepta los términos de uso y la '
                            'política de privacidad.',
                            textAlign: TextAlign.center,
                            style: small,
                          ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () => LegalScreen.open(
                                  context,
                                  const LegalScreen.terms(),
                                ),
                                child: const Text('Términos de uso'),
                              ),
                              TextButton(
                                onPressed: () => LegalScreen.open(
                                  context,
                                  const LegalScreen.privacy(),
                                ),
                                child: const Text('Política de privacidad'),
                              ),
                            ],
                          ),

                          // Solo para soporte y desarrollo: la app ya sale
                          // apuntando al servidor de la universidad.
                          Center(
                            child: TextButton.icon(
                              onPressed: () {
                                setState(() => _showServerConfig = !_showServerConfig);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.ink2,
                              ),
                              icon: Icon(
                                _showServerConfig
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                              ),
                              label: const Text('Servidor'),
                            ),
                          ),
                          if (_showServerConfig) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _serverController,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              style: AppText.code.copyWith(fontSize: 13),
                              maxLines: null,
                              decoration: const InputDecoration(
                                labelText: 'Dirección del servidor',
                                helperText:
                                    'Cámbiela solo si soporte se lo indica. '
                                    'Déjela vacía para usar el servidor de la universidad.',
                              ),
                              validator: (value) {
                                final url = ApiClient.normalizeBaseUrl(value ?? '');
                                if (!_showServerConfig || url.isEmpty) return null;
                                final uri = Uri.tryParse(url);
                                final valid = uri != null &&
                                    uri.hasAuthority &&
                                    (uri.scheme == 'https' || uri.scheme == 'http');
                                return valid
                                    ? null
                                    : 'La dirección debe empezar con https://';
                              },
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: _resetServer,
                                child: const Text('Usar el servidor de la universidad'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
