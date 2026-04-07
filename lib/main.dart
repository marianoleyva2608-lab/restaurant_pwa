import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://jcaqolmacqhhgtjdgvaz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpjYXFvbG1hY3FoaGd0amRndmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3MDExMDIsImV4cCI6MjA4OTI3NzEwMn0.9TS8QZ5ZWG1MOct4nif0yiTW_bq_qbgAGbTjTle1_fk',
  );

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
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6D00), // Gorditas Orange
          brightness: Brightness.dark,
          surface: const Color(0xFF0F172A), // Deep Navy
          onSurface: const Color(0xFFF8FAFC),
          primary: const Color(0xFFFF6D00),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B), // Slate-800
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          centerTitle: false,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFFF8FAFC),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: Color(0xFFF8FAFC), fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: Color(0xFF94A3B8)), // Slate-400
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const RoleSelectionView(),
        '/client': (context) => const ClientHomeView(),
        '/admin': (context) => const AdminView(),
        '/comandas': (context) => const ComandasView(),
        '/cocina': (context) => const KitchenView(),
        '/cocina-llevar': (context) => const KitchenView(isTakeoutOnly: true),
        '/barra': (context) => const KitchenView(isDrinksOnly: true),
        '/ventas': (context) => const ReportsView(),
      },
    );
  }
}
