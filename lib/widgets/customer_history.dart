import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Historial de compras de un cliente (To Go / Domicilio).
///
/// Se reconoce al cliente por su TELÉFONO (lo que viene en customer_name
/// como "... - TEL: 4491234567"). Si la orden no trae teléfono (p.ej. la
/// levantó el mesero solo con nombre), se busca por NOMBRE exacto.
///
/// La consulta se hace SOLO cuando alguien toca "Historial", para no gastar
/// transferencia de Supabase de más.

/// Teléfono a 10 dígitos dentro de customer_name, o null.
String? customerPhone(String? customerName) {
  if (customerName == null) return null;
  final m = RegExp(r'TEL:\s*([0-9 ()+\-]{7,})', caseSensitive: false)
      .firstMatch(customerName);
  if (m == null) return null;
  final digits = m.group(1)!.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 10) return null;
  return digits.substring(digits.length - 10);
}

/// Nombre "limpio": sin "(Pago: …)", " - DIR: …" ni " - TEL: …".
String customerBaseName(String? customerName) {
  final raw = (customerName ?? '').trim();
  final cut = raw.indexOf(RegExp(r'\s*\(Pago:|\s+-\s*DIR:|\s+-\s*TEL:',
      caseSensitive: false));
  return (cut >= 0 ? raw.substring(0, cut) : raw).trim();
}

Future<List<Map<String, dynamic>>> _fetchHistory({
  required String? phone,
  required String name,
  String? excludeOrderId,
}) async {
  final supabase = Supabase.instance.client;
  var q = supabase
      .from('orders')
      .select(
          'id, created_at, branch_name, order_type, total_amount, status, customer_name, '
          'order_items ( quantity, guisados_selected, status, dishes ( name ) )')
      .inFilter('order_type', ['takeout', 'to_go', 'delivery'])
      .neq('status', 'cancelled');
  if (phone != null) {
    // Coincide aunque el número se haya escrito con espacios o guiones:
    // se busca por los últimos 10 dígitos tal cual quedaron guardados.
    q = q.ilike('customer_name', '%TEL:%$phone%');
  } else {
    // Sin teléfono: nombre exacto (con o sin la cola de pago/dirección).
    final safe = name.replaceAll(RegExp(r'[,()%*"\\]'), '').trim();
    if (safe.isEmpty) return [];
    q = q.or('customer_name.ilike."$safe",'
        'customer_name.ilike."$safe (*",'
        'customer_name.ilike."$safe -*"');
  }
  final rows = await q.order('created_at', ascending: false).limit(30);
  return (rows as List)
      .cast<Map<String, dynamic>>()
      .where((o) => o['id'] != excludeOrderId)
      .toList();
}

String _fmtDate(String? iso) {
  if (iso == null) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${meses[d.month - 1]} ${d.year} · $hh:$mm';
}

List<String> _guisados(dynamic raw) {
  if (raw == null) return const [];
  try {
    final v = raw is String ? jsonDecode(raw) : raw;
    if (v is List) return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  } catch (_) {}
  return const [];
}

/// Abre el historial del cliente de [customerName].
Future<void> showCustomerHistory(
  BuildContext context, {
  required String? customerName,
  String? excludeOrderId,
}) async {
  final phone = customerPhone(customerName);
  final name = customerBaseName(customerName);
  if (phone == null && name.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Escribe el nombre o teléfono del cliente')));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => _CustomerHistoryDialog(
      phone: phone,
      name: name,
      excludeOrderId: excludeOrderId,
    ),
  );
}

class _CustomerHistoryDialog extends StatelessWidget {
  final String? phone;
  final String name;
  final String? excludeOrderId;

  const _CustomerHistoryDialog({
    required this.phone,
    required this.name,
    this.excludeOrderId,
  });

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6D00);
    const brown = Color(0xFF3D2E1A);
    const muted = Color(0xFFA08F70);
    return AlertDialog(
      backgroundColor: const Color(0xFFFAF1DE),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name.isEmpty ? 'Cliente' : name,
              style: const TextStyle(color: brown, fontWeight: FontWeight.w800)),
          Text(phone != null ? 'Tel. $phone' : 'Buscado por nombre (sin teléfono)',
              style: const TextStyle(color: muted, fontSize: 12)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchHistory(phone: phone, name: name, excludeOrderId: excludeOrderId),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 120, child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Text('No se pudo cargar el historial: ${snap.error}');
            }
            final orders = snap.data ?? const [];
            if (orders.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Icon(Icons.fiber_new, color: orange),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('Cliente nuevo: no tiene compras anteriores.',
                            style: TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
              );
            }

            // Resumen: compras, gasto y lo que más pide.
            final total = orders.fold<double>(
                0, (s, o) => s + ((o['total_amount'] as num?)?.toDouble() ?? 0));
            final counts = <String, int>{};
            for (final o in orders) {
              for (final it in (o['order_items'] as List? ?? const [])) {
                if (it['status'] == 'cancelled') continue;
                final dn = (it['dishes']?['name'] as String?) ?? '';
                if (dn.isEmpty) continue;
                counts[dn] = (counts[dn] ?? 0) + ((it['quantity'] as num?)?.toInt() ?? 1);
              }
            }
            final top = counts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: orange.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          orders.length >= 3
                              ? '⭐ Cliente frecuente · ${orders.length} compras'
                              : 'Ya compró antes · ${orders.length} ${orders.length == 1 ? 'compra' : 'compras'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, color: orange, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text('Total gastado: \$${total.toStringAsFixed(2)}',
                            style: const TextStyle(color: brown)),
                        Text('Última compra: ${_fmtDate(orders.first['created_at'] as String?)}',
                            style: const TextStyle(color: brown)),
                        if (top.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Lo que más pide: ${top.take(3).map((e) => '${e.key} (${e.value})').join(', ')}',
                            style: const TextStyle(color: brown, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('ÚLTIMAS COMPRAS',
                      style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                  const SizedBox(height: 6),
                  ...orders.take(10).map((o) {
                    final items = (o['order_items'] as List? ?? const [])
                        .where((it) => it['status'] != 'cancelled')
                        .toList();
                    final tipo = o['order_type'] == 'delivery' ? 'Domicilio' : 'To Go';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE5DCC4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(_fmtDate(o['created_at'] as String?),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700, color: brown)),
                              ),
                              Text('\$${((o['total_amount'] as num?) ?? 0).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, color: orange)),
                            ],
                          ),
                          Text('$tipo · ${o['branch_name'] ?? ''}',
                              style: const TextStyle(fontSize: 11, color: muted)),
                          const SizedBox(height: 4),
                          ...items.map((it) {
                            final dn = (it['dishes']?['name'] as String?) ?? 'Envío';
                            final g = _guisados(it['guisados_selected']);
                            return Text(
                              '${it['quantity'] ?? 1}x $dn${g.isNotEmpty ? ' — ${g.join(', ')}' : ''}',
                              style: const TextStyle(fontSize: 12, color: brown),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
    );
  }
}
