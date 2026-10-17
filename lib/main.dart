import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/cart_provider.dart';
import 'views/role_selection_view.dart';
import 'views/client_home_view.dart';
import 'globals.dart';
import 'views/admin_view.dart';
import 'views/comandas_view.dart';
import 'views/kitchen_view.dart';
import 'views/reports_view.dart';
import 'views/mesero_login_view.dart';
import 'views/ticket_view.dart';
import 'widgets/subscription_gate.dart';

/// Build-time flag: si la app se compila con --dart-define=KIOSKO_MESERO=true,
/// arranca directo en la pantalla de mesero y deshabilita la selección de rol.
/// Pensado para el APK de tablet que va a ser el "App de inicio" de un tablet
/// en modo kiosko.
const bool kKioskoMesero =
    bool.fromEnvironment('KIOSKO_MESERO', defaultValue: false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enlace de cliente: bloquear los paneles internos en esta sesión.
  if (kIsWeb) {
    final frag = Uri.base.fragment;
    // Dirección exclusiva de clientes (p.ej. pedidos-gorditas.…): siempre
    // es solo el panel de pedidos, aunque recarguen o cambien la ruta.
    final host = Uri.base.host.toLowerCase();
    if (host.contains('pedidos') ||
        frag.startsWith('/client') ||
        frag.startsWith('/ticket')) {
      Globals.clientOnly = true;
    }
  }

  // En modo kiosko en Android: pantalla completa inmersiva y bloqueo de
  // rotación a horizontal/vertical natural del tablet.
  if (kKioskoMesero && !kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }

  // Límite de tiempo en el arranque: si la conexión a Supabase se cuelga
  // aquí (sin fallar ni completarse), la pantalla se quedaría en blanco
  // para siempre porque runApp() nunca se llama. Con el timeout, la app
  // arranca igual (con lo que haya en caché/default) en vez de trabarse.
  try {
    await Supabase.initialize(
      url: 'https://jcaqolmacqhhgtjdgvaz.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpjYXFvbG1hY3FoaGd0amRndmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3MDExMDIsImV4cCI6MjA4OTI3NzEwMn0.9TS8QZ5ZWG1MOct4nif0yiTW_bq_qbgAGbTjTle1_fk',
    ).timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('Supabase.initialize tardó demasiado o falló: $e');
  }

  await Globals.loadBranch();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: const RestaurantApp(),
    ),
  );
}

class RestaurantApp extends StatelessWidget {
  const RestaurantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gorditas Mis Hermanas',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6D00), // Gorditas Orange
          brightness: Brightness.light,
          surface: const Color(0xFFFAF1DE), // Cream
          onSurface: const Color(0xFF3D2E1A), // Dark brown
          primary: const Color(0xFFFF6D00),
        ),
        scaffoldBackgroundColor: const Color(0xFFFAF1DE),
        cardTheme: CardThemeData(
          color: const Color(0xFFFAF1DE),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAF1DE),
          foregroundColor: Color(0xFFFF6D00),
          centerTitle: false,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFFFF6D00),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Color(0xFFFF6D00)),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: Color(0xFF3D2E1A), fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: Color(0xFF7A6E5A)),
        ),
        dividerColor: const Color(0xFFE5DCC4),
        iconTheme: const IconThemeData(color: Color(0xFFFF6D00)),
      ),
      initialRoute: '/',
      // Si se entró con el enlace de cliente, toda ruta interna muestra el
      // panel de pedidos del cliente (no se puede llegar a los demás paneles).
      routes: {
        '/': (context) => Globals.clientOnly
            ? const ClientHomeView()
            : SubscriptionGate(
                child: kKioskoMesero
                    ? const MeseroLoginView()
                    : const RoleSelectionView(),
              ),
        '/client': (context) => const ClientHomeView(),
        '/admin': (context) =>
            Globals.clientOnly ? const ClientHomeView() : const AdminView(),
        '/comandas': (context) =>
            Globals.clientOnly ? const ClientHomeView() : const ComandasView(),
        '/cocina': (context) =>
            Globals.clientOnly ? const ClientHomeView() : const KitchenView(),
        '/cocina-llevar': (context) => Globals.clientOnly
            ? const ClientHomeView()
            : const KitchenView(isTakeoutOnly: true),
        '/barra': (context) => Globals.clientOnly
            ? const ClientHomeView()
            : const KitchenView(isDrinksOnly: true),
        '/ventas': (context) =>
            Globals.clientOnly ? const ClientHomeView() : const ReportsView(),
        '/mesero': (context) =>
            Globals.clientOnly ? const ClientHomeView() : const MeseroLoginView(),
      },
      // Maneja rutas dinámicas tipo /{sucursal}/mesero y /ticket/{orderId}
      // Ejemplo: /#/Maravillas/mesero → branch "Sucursal Maravillas"
      // Ejemplo: /#/ticket/abc-1234   → TicketView para esa orden
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        final segments = name.split('/').where((s) => s.isNotEmpty).toList();
        // /ticket/{orderId} — vista pública del ticket accedida por QR.
        if (segments.length == 2 && segments.first == 'ticket') {
          final orderId = Uri.decodeComponent(segments.last);
          return MaterialPageRoute(
            builder: (_) => TicketView(orderId: orderId),
            settings: settings,
          );
        }
        if (Globals.clientOnly) {
          return MaterialPageRoute(
            builder: (_) => const ClientHomeView(),
            settings: settings,
          );
        }
        if (segments.length == 2 && segments.last == 'mesero') {
          final slug = Uri.decodeComponent(segments.first);
          // Busca rama exacta primero, luego "Sucursal {slug}"
          final branch = Globals.branches.firstWhere(
            (b) => b.toLowerCase() == slug.toLowerCase(),
            orElse: () => Globals.branches.firstWhere(
              (b) => b.toLowerCase().contains(slug.toLowerCase()),
              orElse: () => slug,
            ),
          );
          return MaterialPageRoute(
            builder: (_) => MeseroLoginView(branch: branch),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}
