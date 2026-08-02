import 'package:supabase/supabase.dart';

/// Diagnóstico: ¿por qué algunas órdenes To Go / Delivery no aparecen en
/// "Vista General" para cobrar, aunque su comanda sí se haya impreso?
///
/// Lista TODAS las órdenes sin mesa (table_id null) de las últimas 24h,
/// con su status, sucursal, mesero, folio y cantidad de items — sin
/// filtrar por status/branch como hace la app, para ver exactamente
/// qué está pasando con cada una.
///
/// Uso: dart run check_togo_orders.dart
void main() async {
  final supabase = SupabaseClient(
    'https://jcaqolmacqhhgtjdgvaz.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpjYXFvbG1hY3FoaGd0amRndmF6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM3MDExMDIsImV4cCI6MjA4OTI3NzEwMn0.9TS8QZ5ZWG1MOct4nif0yiTW_bq_qbgAGbTjTle1_fk',
  );

  final since = DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();

  final orders = await supabase
      .from('orders')
      .select('id, customer_name, status, branch_name, order_type, waiter_id, daily_folio, table_id, total_amount, created_at, sent_to_kitchen_at, printed_at')
      .isFilter('table_id', null)
      .gte('created_at', since)
      .order('created_at');

  final list = (orders as List).cast<Map<String, dynamic>>();

  if (list.isEmpty) {
    print('No hay órdenes sin mesa en las últimas 24h.');
    return;
  }

  print('Total órdenes To Go/Delivery (últimas 24h): ${list.length}\n');

  for (final o in list) {
    // Cuenta cuántos order_items tiene cada orden, para ver si de verdad
    // se guardaron los artículos (y no se perdieron/mezclaron).
    final items = await supabase
        .from('order_items')
        .select('id, quantity, status')
        .eq('order_id', o['id']);
    final itemCount = (items as List).length;

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('Folio: #${o['daily_folio']}');
    print('  id: ${o['id']}');
    print('  cliente: ${o['customer_name']}');
    print('  tipo: ${o['order_type']}');
    print('  status: ${o['status']}   <-- la app solo muestra pending/ready/incomplete');
    print('  sucursal: ${o['branch_name']}');
    print('  waiter_id: ${o['waiter_id']}');
    print('  total: \$${o['total_amount']}');
    print('  items guardados: $itemCount');
    print('  creado: ${o['created_at']}');
    print('  enviado a cocina: ${o['sent_to_kitchen_at']}');
    print('  impreso: ${o['printed_at']}');
  }
}
