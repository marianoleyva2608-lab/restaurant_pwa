import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Vista pública del ticket virtual. Se accede vía /ticket/{orderId}
// desde el QR que se muestra en el checkout tras aprobar el pago.
// El orderId es un UUID → sirve como token público (imposible de adivinar).
class TicketView extends StatefulWidget {
  final String orderId;
  const TicketView({super.key, required this.orderId});

  @override
  State<TicketView> createState() => _TicketViewState();
}

class _TicketViewState extends State<TicketView> {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await _supabase
          .from('orders')
          .select('''
            id, branch_name, order_type, customer_name, total_amount,
            status, created_at, payment_method,
            restaurant_tables ( table_number )
          ''')
          .eq('id', widget.orderId)
          .maybeSingle();
      if (order == null) {
        setState(() {
          _error = 'No encontramos esta orden.';
          _loading = false;
        });
        return;
      }
      final items = await _supabase
          .from('order_items')
          .select('''
            id, quantity, price_at_time, guisados_selected,
            dishes ( name, category )
          ''')
          .eq('order_id', widget.orderId)
          .order('id', ascending: true);
      setState(() {
        _order = order;
        _items = List<Map<String, dynamic>>.from(items);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No pudimos cargar el ticket. ($e)';
        _loading = false;
      });
    }
  }

  String _orderTypeLabel(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'dine_in':
        return 'COMER AQUÍ';
      case 'to_go':
      case 'takeout':
        return 'PARA LLEVAR';
      case 'delivery':
        return 'A DOMICILIO';
      default:
        return (raw ?? 'PEDIDO').toUpperCase();
    }
  }

  String _statusLabel(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'pending':
        return 'En cocina';
      case 'ready':
        return 'Listo';
      case 'delivered':
        return 'Entregado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return raw ?? '—';
    }
  }

  ({String fraction, String cleanName}) _parseSize(String name) {
    final s = name.trim();
    final half = RegExp(r'\s*\(1\/2\)(\s+ord[eé]n(es)?)?\s*$', caseSensitive: false).firstMatch(s);
    if (half != null) {
      return (fraction: '1/2', cleanName: s.substring(0, half.start).trim());
    }
    final whole = RegExp(r'\s*\(ord[eé]n(es)?\)\s*$', caseSensitive: false).firstMatch(s);
    if (whole != null) {
      return (fraction: '1', cleanName: s.substring(0, whole.start).trim());
    }
    return (fraction: '', cleanName: s);
  }

  List<String> _parseGuisados(dynamic raw) {
    if (raw == null) return const [];
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is List) {
        return decoded.whereType<String>().where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    return const [];
  }

  String _parseCustomerDisplayName(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final m = RegExp(r'^([^()\-]+)').firstMatch(raw);
    return (m?.group(1) ?? raw).trim();
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(d.day)}/${pad(d.month)}/${d.year} ${pad(d.hour)}:${pad(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tu Ticket')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildTicket(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildTicket() {
    final order = _order!;
    final tableNumber = order['restaurant_tables']?['table_number'];
    final customerName = _parseCustomerDisplayName(order['customer_name'] as String?);
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(order),
                  const SizedBox(height: 16),
                  const Divider(),
                  _buildInfoRow('Tipo', _orderTypeLabel(order['order_type'] as String?)),
                  if (tableNumber != null) _buildInfoRow('Mesa', '$tableNumber'),
                  if (customerName.isNotEmpty) _buildInfoRow('Cliente', customerName),
                  _buildInfoRow('Fecha', _formatDate(order['created_at'] as String?)),
                  _buildInfoRow('Estado', _statusLabel(order['status'] as String?)),
                  const Divider(),
                  const SizedBox(height: 8),
                  ..._items.map(_buildItemRow),
                  const SizedBox(height: 12),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'ID: ${order['id'].toString().substring(0, 8)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> order) {
    return Column(
      children: [
        const Text(
          'GORDITAS MIS HERMANAS',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        if (order['branch_name'] != null) ...[
          const SizedBox(height: 4),
          Text(
            order['branch_name'] as String,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildItemRow(Map<String, dynamic> it) {
    final rawName = (it['dishes']?['name'] as String?) ?? '(sin nombre)';
    final parsed = _parseSize(rawName);
    final qty = (it['quantity'] as num?)?.toInt() ?? 1;
    final line = parsed.fraction.isNotEmpty
        ? '${qty}x${parsed.fraction} ${parsed.cleanName}'
        : '${qty}x ${parsed.cleanName}';
    final guisados = _parseGuisados(it['guisados_selected']);
    final price = (it['price_at_time'] as num?)?.toDouble() ?? 0;
    final subtotal = price * qty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(line, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              Text('\$${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
            ],
          ),
          if (guisados.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text(
                guisados.join(', '),
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
