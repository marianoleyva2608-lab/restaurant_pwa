import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://jcaqolmacqhhgtjdgvaz.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpjYXFvbG1hY3FoaGd0amRndmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3MDExMDIsImV4cCI6MjA4OTI3NzEwMn0.9TS8QZ5ZWG1MOct4nif0yiTW_bq_qbgAGbTjTle1_fk',
  );

  final waiters = await client.from('waiters').select();
  print('--- MESEROS REGISTRADOS ---');
  for (var w in waiters) {
    print('Nombre: ${w['name']} | PIN: ${w['pin']} | Sucursal: ${w['branch_name']}');
  }
}
