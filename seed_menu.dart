import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  final supabase = SupabaseClient(
    'https://jcaqolmacqhhgtjdgvaz.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpjYXFvbG1hY3FoaGd0amRndmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3MDExMDIsImV4cCI6MjA4OTI3NzEwMn0.9TS8QZ5ZWG1MOct4nif0yiTW_bq_qbgAGbTjTle1_fk',
  );
  
  print('Deleting existing dishes...');
  // WARNING: DELETES ALL DISHES. IF WE ONLY WANT TO DELETE AND REPOPULATE GORDITAS OR MATRIZ, we should filter.
  // The global branch name from the app is usually "Matriz" by default. Let's delete all and re-seed "Matriz".
  try {
    await supabase.from('dishes').delete().neq('id', '00000000-0000-0000-0000-000000000000'); // Deletes all
  } catch (e) {
    print('No errors on delete $e');
  }

  final String branch = 'Sucursal 1';

  final List<Map<String, dynamic>> menuItems = [
    // TAPAS DE GUISADO
    {'name': 'Tapas de Guisado (5 pzas.)', 'price': 100, 'category': 'mainCourse'},
    {'name': 'Tapas de Guisado con Queso (5 pzas.)', 'price': 125, 'category': 'mainCourse'},

    // ÓRDENES EXTRAS
    {'name': 'Orden Extra - Tocino o jamón (3 pzas.)', 'price': 30, 'category': 'appetizer'},
    {'name': 'Orden Extra - Guisado', 'price': 40, 'category': 'appetizer'},
    {'name': 'Orden Extra - Arrachera', 'price': 40, 'category': 'appetizer'},
    {'name': 'Orden Extra - Huevo estrellado o revuelto', 'price': 20, 'category': 'appetizer'},
    {'name': 'Orden Extra - Pieza de bolillo', 'price': 16, 'category': 'appetizer'},

    // MENUDO
    {'name': 'Menudo Chico', 'price': 90, 'category': 'mainCourse'},
    {'name': 'Menudo Mediano', 'price': 100, 'category': 'mainCourse'},
    {'name': 'Menudo Grande', 'price': 110, 'category': 'mainCourse'},
    {'name': 'Cuajadilla Chica (tortilla tortilleria)', 'price': 30, 'category': 'mainCourse'},
    {'name': 'Cuajadilla Grande (tortilla a mano)', 'price': 70, 'category': 'mainCourse'},

    // BEBIDAS
    {'name': 'Café de Olla con refill', 'price': 45, 'category': 'drink'},
    {'name': 'Café Instantáneo', 'price': 45, 'category': 'drink'},
    {'name': 'Jugo Verde (vaso 330 ml)', 'price': 45, 'category': 'drink'},
    {'name': 'Jugo Verde (1 litro)', 'price': 125, 'category': 'drink'},
    {'name': 'Jugo de Naranja natural (vaso 330 ml)', 'price': 40, 'category': 'drink'},
    {'name': 'Jugo de Naranja natural (1 litro)', 'price': 110, 'category': 'drink'},
    {'name': 'Jugo de Zanahoria natural (vaso 330 ml)', 'price': 38, 'category': 'drink'},
    {'name': 'Jugo de Zanahoria natural (1 litro)', 'price': 95, 'category': 'drink'},
    {'name': 'Agua Fresca (vaso 600 ml)', 'price': 35, 'category': 'drink'},
    {'name': 'Agua Fresca (1 litro)', 'price': 60, 'category': 'drink'},
    {'name': 'Agua Fresca (2 litros)', 'price': 100, 'category': 'drink'},
    {'name': 'Agua Natural (500 ml)', 'price': 14, 'category': 'drink'},
    {'name': 'Refresco (355 ml vidrio)', 'price': 30, 'category': 'drink'},
    {'name': 'Refresco (600 ml no retornable)', 'price': 40, 'category': 'drink'},
    {'name': 'Vaso de leche (330 ml)', 'price': 35, 'category': 'drink'},
    {'name': 'Choco (600 ml)', 'price': 40, 'category': 'drink'},
    {'name': 'Té', 'price': 35, 'category': 'drink'},

    // PARA LLEVAR
    {'name': '1/2 litro Guisado con carne', 'price': 120, 'category': 'mainCourse'},
    {'name': '1/2 litro Guisado sin carne', 'price': 80, 'category': 'mainCourse'},
    {'name': '1/2 litro Arroz o Frijoles', 'price': 40, 'category': 'mainCourse'},
    {'name': '1/4 litro Salsa', 'price': 40, 'category': 'mainCourse'},
    {'name': 'Chile Relleno con salsa', 'price': 50, 'category': 'mainCourse'},

    // OTROS (Images 2 & 3)
    {'name': 'Hot Cakes (2 pzas.)', 'price': 70, 'category': 'mainCourse'},
    {'name': 'Molletes de Chilaquiles', 'price': 130, 'category': 'mainCourse'},
    {'name': 'Molletes Dulces', 'price': 80, 'category': 'mainCourse'},
    {'name': 'Huevos Divorciados', 'price': 90, 'category': 'mainCourse'},
    {'name': 'Chilaquiles Verdes', 'price': 95, 'category': 'mainCourse'},
  ];

  print('Inserting new dishes...');
  for (var item in menuItems) {
    item['branch_name'] = branch;
    await supabase.from('dishes').insert(item);
  }
  
  print('Done seeding menu items!');
  exit(0);
}
