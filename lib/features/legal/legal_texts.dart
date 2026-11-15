/// Textos de la política de privacidad y de los términos de uso.
///
/// La web tiene una copia en `taller-frontend/src/lib/legal.ts`: si se cambia
/// uno, cambiar también el otro.
library;

class LegalSection {
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;

  const LegalSection(
    this.title, {
    this.paragraphs = const [],
    this.bullets = const [],
  });
}

class LegalDocument {
  final String title;
  final String updated;
  final String intro;
  final List<LegalSection> sections;

  const LegalDocument({
    required this.title,
    required this.updated,
    required this.intro,
    required this.sections,
  });
}

const String legalUpdated = '15/11/2026';

const LegalDocument privacyPolicy = LegalDocument(
  title: 'Política de privacidad',
  updated: legalUpdated,
  intro:
      'Esta política explica qué datos guarda el sistema de diagnóstico vehicular preventivo del parque automotor de la Universidad Autónoma Gabriel René Moreno (UAGRM), para qué los usa y con quién los comparte. Se aplica a la plataforma web y a la aplicación móvil.',
  sections: [
    LegalSection('Responsable', paragraphs: [
      'El responsable de los datos es el administrador del sistema del parque automotor de la UAGRM. Las consultas sobre esta política se le dirigen a él.',
    ]),
    LegalSection('Qué datos se guardan', bullets: [
      'De su cuenta: nombre, correo electrónico, rol y la contraseña cifrada (nunca se guarda tal como se escribe).',
      'De los vehículos: placa, número de chasis (VIN), marca, modelo y año.',
      'De cada escaneo: códigos de falla, voltaje de la batería, estado de los monitores del vehículo, la observación del inspector, quién lo hizo y cuándo.',
      'De las órdenes de trabajo: descripción, notas de avance, a quién está asignada, quién la cerró y cuándo.',
      'De su teléfono: un identificador que entrega Firebase para enviarle notificaciones. Se borra al cerrar sesión.',
    ]),
    LegalSection('Qué no se guarda', bullets: [
      'Los valores del monitor en vivo: se muestran solo en el teléfono y se descartan al cerrarlo.',
      'Su ubicación. Android exige el permiso de ubicación para buscar dispositivos Bluetooth, pero la aplicación no la lee ni la envía.',
    ]),
    LegalSection('Para qué se usan', paragraphs: [
      'Para el mantenimiento preventivo de los vehículos de la universidad: registrar los escaneos, detectar fallas, generar y seguir órdenes de trabajo, avisar al personal responsable y emitir reportes. No se usan con fines comerciales.',
    ]),
    LegalSection(
      'Con quién se comparten',
      paragraphs: ['El sistema se apoya en estos servicios externos:'],
      bullets: [
        'Anthropic (inteligencia artificial): recibe los datos del vehículo y del escaneo para proponer una hipótesis técnica. No recibe nombres ni correos de personas.',
        'Firebase, de Google: entrega las notificaciones push al teléfono.',
        'n8n, Telegram y correo electrónico: envían los avisos de órdenes nuevas y el resumen diario.',
        'Neon: aloja la base de datos.',
        'Microsoft Azure: aloja el servidor.',
      ],
    ),
    LegalSection('Cuánto tiempo se conservan', paragraphs: [
      'Mientras sirvan al mantenimiento del parque automotor. Dar de baja un vehículo o desactivar una cuenta no borra su historial, porque los escaneos y las órdenes son el registro técnico de cada vehículo.',
    ]),
    LegalSection('Sus derechos', paragraphs: [
      'Puede pedir al administrador que le muestre o corrija sus datos, o que desactive su cuenta.',
    ]),
    LegalSection('Seguridad', paragraphs: [
      'Las contraseñas se guardan cifradas, las conexiones viajan cifradas y cada persona accede solo a lo que su rol permite.',
    ]),
    LegalSection('Cambios', paragraphs: [
      'Si esta política cambia, la versión nueva se publica en esta misma página con su fecha de actualización.',
    ]),
  ],
);

const LegalDocument termsOfUse = LegalDocument(
  title: 'Términos de uso',
  updated: legalUpdated,
  intro:
      'Estos términos rigen el uso de la plataforma web y de la aplicación móvil de diagnóstico vehicular preventivo de la UAGRM. Al iniciar sesión, usted los acepta.',
  sections: [
    LegalSection('Quién puede usarlo', paragraphs: [
      'El sistema es de uso exclusivo del personal autorizado de la UAGRM. Las cuentas las crea el administrador del sistema.',
    ]),
    LegalSection('Su cuenta', paragraphs: [
      'La cuenta es personal. No comparta su contraseña: cada escaneo, nota y cierre de orden queda registrado a nombre de quien inició sesión.',
    ]),
    LegalSection('La hipótesis de inteligencia artificial', paragraphs: [
      'La hipótesis que genera la inteligencia artificial es orientativa y no reemplaza la revisión de un mecánico. La decisión técnica es siempre de una persona, y solo quien tiene ese permiso autoriza que un vehículo vuelva a operar.',
    ]),
    LegalSection('El escaneo', bullets: [
      'Conecte el adaptador con el vehículo detenido y en condiciones seguras.',
      'Verifique que el vehículo elegido sea el que está escaneando.',
      'Que no aparezcan códigos de falla no garantiza que el vehículo esté en buen estado.',
    ]),
    LegalSection('Usos no permitidos', paragraphs: [
      'No está permitido alterar datos a sabiendas, usar la cuenta de otra persona ni intentar acceder a funciones que su rol no permite. El administrador puede desactivar la cuenta de quien incumpla estos términos.',
    ]),
    LegalSection('Disponibilidad', paragraphs: [
      'El sistema puede tener interrupciones por mantenimiento o por fallas de los servicios externos de los que depende.',
    ]),
    LegalSection('Carácter académico', paragraphs: [
      'El sistema se desarrolló como trabajo de grado y puede cambiar. Los cambios en estos términos se publican en esta misma página con su fecha de actualización.',
    ]),
  ],
);
