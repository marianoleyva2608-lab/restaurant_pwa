import 'dart:io';
import 'package:supabase/supabase.dart';

/// Inserta "Café Instantáneo" en la base de datos si todavía no existe,
/// con el mismo precio y costo que "Café Americano". Se agrupa dentro de
/// "Cafés" en la app automáticamente porque el nombre contiene
/// "instantáneo" (ver _drinkSubcat en comandas_view.dart / menu_browser.dart).
///
/// Uso: dart run add_cafe_instantaneo.dart
void main() async {
  final supabase = SupabaseClient(
    'https://jcaqolmacqhhgtjdgvaz.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpjYXFvbG1hY3FoaGd0amRndmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3MDExMDIsImV4cCI6MjA4OTI3NzEwMn0.9TS8QZ5ZWG1MOct4nif0yiTW_bq_qbgAGbTjTle1_fk',
  );

  const nombre = 'Café Instantáneo';

  print('Buscando si ya existe "$nombre"...');
  final existentes = await supabase
      .from('dishes')
      .select('id, name, category, price')
      .ilike('name', '%instant%');
  final yaExiste = (existentes as List).cast<Map<String, dynamic>>();

  if (yaExiste.isNotEmpty) {
    print('Ya existe(n) ${yaExiste.length} platillo(s) con "instant" en el nombre:');
    for (final d in yaExiste) {
      print('  - ${d['name']} | categoría: ${d['category']} | precio: ${d['price']}');
    }
    print('\nNo se insertó nada para evitar duplicados.');
    exit(0);
  }

  print('Buscando el precio de "Café Americano" para igualarlo...');
  final americanos = await supabase
      .from('dishes')
      .select('id, name, category, price, cost')
      .ilike('name', '%american%');
  final list = (americanos as List).cast<Map<String, dynamic>>();

  num price;
  num cost;
  if (list.isNotEmpty) {
    final ref = list.first;
    price = ref['price'] as num;
    cost = (ref['cost'] as num?) ?? 0;
    print('  Encontrado: "${ref['name']}" a \$${ref['price']}. Se usará ese precio.');
  } else {
    price = 45;
    cost = 0;
    print('  No se encontró "Café Americano" en la base. Se usará \$45 por default.');
  }

  print('Insertando "$nombre" a \$$price...');
  try {
    await supabase.from('dishes').insert({
      'name': nombre,
      'description': '',
      'price': price,
      'cost': cost,
      'category': 'drink',
      'requires_guisado': false,
      'max_time': 5,
    });
    print('✔ "$nombre" insertado correctamente (precio \$$price) en la categoría "drink".');
    print('  Aparecerá dentro de "Cafés" en el picker de Bebidas.');
  } catch (e) {
    print('✗ Error al insertar: $e');
    exit(1);
  }
}
