# Taller Mobile — Flutter

Aplicación Android de diagnóstico vehicular preventivo del parque automotor de
la UAGRM. Lee el vehículo por el puerto OBD-II con un adaptador ELM327
(Bluetooth Classic) y envía el escaneo al backend.

## Requisitos

- Flutter 3.35+ (la versión está fijada en `.fvmrc`)
- Android Studio con el SDK de Android
- Un teléfono o emulador Android

## Inicio rápido

```bash
flutter pub get
flutter run
```

## Servidor

La app sale apuntando al backend desplegado en Azure:

```
https://taller-backend.proudriver-ee00705b.canadacentral.azurecontainerapps.io/api
```

No hay que configurar nada para usarla ni para generar el APK
(`flutter build apk --release`).

Para desarrollar contra un backend local, fije otra dirección al ejecutar:

```bash
# Emulador de Android (10.0.2.2 es el localhost de la PC)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api

# Teléfono real en la misma red
flutter run --dart-define=API_BASE_URL=http://<IP_DE_LA_PC>:3000/api
```

También se puede cambiar en un teléfono ya instalado, desde «Servidor» en la
pantalla de inicio de sesión. Android solo permite direcciones `http://` en
compilaciones de depuración; el APK de producción exige `https://`.

El backend desplegado se apaga cuando no tiene uso. La primera solicitud
después de un rato puede tardar hasta un minuto: la app espera y lo avisa.

## Diseño

La app usa el mismo sistema de diseño que la plataforma web
(`taller-frontend/src/app/globals.css`), definido en
`lib/core/theme/app_theme.dart`:

- **Marca** (azul marino y borgoña de las siglas): estructura y acciones.
- **Estado** (verde, ámbar, rojo): solo para decir cómo está un vehículo, un
  escaneo o una orden. Nunca como decoración.
- **Neutros**: todo lo demás.

Las pantallas no usan colores sueltos (`Colors.blue`, etc.): toman los de
`AppColors` y los componentes de `lib/core/ui/`. Las etiquetas de estado
(`badges.dart`) llevan los mismos textos que la web.

## Estructura

```
lib/
├── core/
│   ├── api/          # Cliente HTTP del backend
│   ├── auth/         # Sesión y permisos
│   ├── bluetooth/    # Conexión Bluetooth Classic
│   ├── elm327/       # Protocolo ELM327 y monitor en vivo
│   ├── push/         # Notificaciones push (Firebase)
│   ├── theme/        # Colores, tipografía y tema
│   └── ui/           # Componentes compartidos (avisos, etiquetas, paneles)
├── features/
│   ├── alerts/       # Detalle de la orden que abre una notificación
│   ├── auth/         # Inicio de sesión y cuenta
│   ├── history/      # Historial de escaneos
│   ├── legal/        # Términos y privacidad
│   ├── monitor/      # Monitor en vivo
│   ├── scan/         # Escaneo
│   └── vehicles/     # Vehículos
├── simulator/        # ELM327 simulado, para trabajar sin adaptador
└── main.dart
```

## Simulador

La pantalla «Escanear» trae un interruptor «Usar el simulador» con varios
escenarios de prueba (`lib/simulator/mock_elm327.dart`). Los escaneos del
simulador se envían al servidor igual que los reales.

## Pruebas

```bash
flutter analyze
flutter test
```
