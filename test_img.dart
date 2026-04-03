import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final supabase = SupabaseClient(
    'https://jcaqolmacqhhgtjdgvaz.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpjYXFvbG1hY3FoaGd0amRndmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3MDExMDIsImV4cCI6MjA4OTI3NzEwMn0.9TS8QZ5ZWG1MOct4nif0yiTW_bq_qbgAGbTjTle1_fk',
  );
  
  final res = await supabase.from('dishes').select().eq('branch_name', 'Sucursal 1');
  bool found = false;
  for (var row in res) {
    var img = row['image_url'];
    if (img == null) {
      print('ID: ${row['id']} HAS NULL IMAGE');
      found=true;
    } else if (img == '') {
      print('ID: ${row['id']} HAS EMPTY STRING IMAGE');
      found=true;
    } else {
      print('ID: ${row['id']} IMG: $img');
    }
  }
  if (!found) print('No empty images');
  exit(0);
}
