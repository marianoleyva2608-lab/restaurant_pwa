import 'package:supabase/supabase.dart';

void main() async {
  print('Iniciando prueba de conexión realtime...');
  final supabase = SupabaseClient(
    'https://jcaqolmacqhhgtjdgvaz.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpjYXFvbG1hY3FoaGd0amRndmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3MDExMDIsImV4cCI6MjA4OTI3NzEwMn0.9TS8QZ5ZWG1MOct4nif0yiTW_bq_qbgAGbTjTle1_fk',
  );

  print('Cliente Supabase inicializado. Suscribiendo a cambios en la tabla orders mediante stream()...');
  
  try {
    supabase.from('orders').stream(primaryKey: ['id']).listen((List<Map<String, dynamic>> data) {
      print('¡Stream actualizado! Cantidad de órdenes: ${data.length}');
      if (data.isNotEmpty) {
        print('Última orden: ${data.last['id']} con estado ${data.last['status']}');
      }
    }, onError: (err) {
      print('Error en stream: $err');
    }, onDone: () {
      print('Stream terminado.');
    });

    // Keep active
    await Future.delayed(Duration(days: 1));
  } catch (e) {
    print('Error de inicialización: $e');
  }
}
