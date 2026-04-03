import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final supabase = SupabaseClient(
    'https://jcaqolmacqhhgtjdgvaz.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpjYXFvbG1hY3FoaGd0amRndmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3MDExMDIsImV4cCI6MjA4OTI3NzEwMn0.9TS8QZ5ZWG1MOct4nif0yiTW_bq_qbgAGbTjTle1_fk',
  );
  
  final res = await supabase.from('dishes').select().eq('branch_name', 'Sucursal 1');
  for (var row in res) {
    if (row['image_url'] == '') {
       print('ID: ${row['id']} HAS EMPTY IMAGE URL');
    }
  }
  print('Done checking empty image urls');
  exit(0);
}
