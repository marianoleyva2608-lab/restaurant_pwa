import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../globals.dart';

/// Mismas categorías que cuentan como bebida en kitchen_view.dart y en
/// print-worker/index.js (DRINK_CATEGORIES). Mantenerlas sincronizadas.
const _drinkCategories = [
  'drink', 'alcohol', 'bebidas', 'drinks', 'aguas', 'jugos', 'cafes', 'refrescos',
];

bool _isDrinkCategory(String? category) =>
    _drinkCategories.contains((category ?? '').toLowerCase().trim());

/// Espejo de `correctDrinkName` en print-worker/index.js: refrescos/aguas/
/// jugos comparten un solo dish_id representativo sin importar el TAMAÑO
/// elegido, así que `dishes.name` puede no reflejar el tamaño real — el
/// primer guisado sí lo trae (ej. "600 ml"), y de ahí reconstruimos el
/// nombre correcto para que el ticket simulado coincida con el impreso.
String _correctDrinkName(String rawName, List<String> guisados) {
  if (guisados.isEmpty) return rawName;
  final sizeStr = guisados.first.trim();
  if (!RegExp(r'^\d+\s?(ml|litro)$', caseSensitive: false).hasMatch(sizeStr)) return rawName;
  final n = rawName.toLowerCase();
  if (n.contains('refresco')) {
    if (sizeStr.contains('355')) return 'Refresco de vidrio';
    if (sizeStr.contains('600')) return 'Refresco no retornable';
    return 'Refresco';
  }
  if (n.contains('jugo')) return 'Jugo';
  if (n.contains('agua') && !n.contains('natural')) return 'Agua Fresca';
  return rawName;
}

/// Áreas físicas esperadas (una Raspberry por cada una). 'kitchen' y
/// 'line' son el mismo rol (cocina) con nombre distinto según sucursal
/// — ver print-worker/README.md.
const _expectedPrintAreas = [
  (['drinks'], 'Bebidas', Icons.local_bar),
  (['kitchen', 'line'], 'Cocina/Línea', Icons.soup_kitchen),
  (['takeout'], 'Para Llevar', Icons.takeout_dining),
  (['receipt'], 'Caja/Recibo', Icons.receipt_long),
];

/// Cuánto tiempo sin heartbeat antes de considerar una Pi "desconectada".
/// El print-worker manda uno cada 20s — 45s da margen a que se le pase
/// un ciclo sin marcarla como caída de inmediato.
const _heartbeatStaleAfter = Duration(seconds: 45);

/// Pantalla de solo lectura: para cada orden activa, muestra si ya se
/// imprimió en cada área física (Bebidas, y Cocina o Para Llevar según
/// el tipo de orden) — sin tener que revisar Supabase ni las Raspberries
/// a mano. Se basa en `order_items.printed_at`, que cada Pi marca al
/// imprimir sus items (ver print-worker/index.js).
class PrintStatusView extends StatefulWidget {
  const PrintStatusView({super.key});

  @override
  State<PrintStatusView> createState() => _PrintStatusViewState();
}

class _PrintStatusViewState extends State<PrintStatusView> {
  final _supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Estado de Impresión',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFFFF6D00)),
                tooltip: 'Actualizar',
                onPressed: () => setState(() {}),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 16),
            child: Text(
              'Qué órdenes activas ya se imprimieron en cada área (Bebidas, Cocina/Para Llevar). '
              'Los LEDs de conexión están en la barra de abajo.',
              style: TextStyle(color: Color(0xFFA08F70)),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('restaurant_tables')
                  .stream(primaryKey: ['id'])
                  .eq('branch_name', Globals.currentBranch),
              builder: (context, tablesSnapshot) {
                final tableNumbers = <String, dynamic>{
                  for (final t in (tablesSnapshot.data ?? const []))
                    t['id'] as String: t['table_number'],
                };

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _supabase
                      .from('orders')
                      .stream(primaryKey: ['id'])
                      .inFilter('status', ['pending', 'ready', 'incomplete']),
                  builder: (context, orderSnapshot) {
                    if (!orderSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final orders = orderSnapshot.data!
                        .where((o) => o['branch_name'] == Globals.currentBranch)
                        .toList()
                      ..sort((a, b) => (a['created_at'] as String? ?? '')
                          .compareTo(b['created_at'] as String? ?? ''));

                    if (orders.isEmpty) {
                      return const Center(
                        child: Text('No hay órdenes activas.',
                            style: TextStyle(color: Colors.grey)),
                      );
                    }

                    final orderIds = orders.map((o) => o['id'] as String).toList();

                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _supabase
                          .from('order_items')
                          .stream(primaryKey: ['id'])
                          .inFilter('order_id', orderIds)
                          .asyncMap((_) async {
                            final rows = await _supabase
                                .from('order_items')
                                .select('id, order_id, printed_at, status, dishes(name, category)')
                                .inFilter('order_id', orderIds);
                            return List<Map<String, dynamic>>.from(rows);
                          }),
                      builder: (context, itemsSnapshot) {
                        if (!itemsSnapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final allItems = itemsSnapshot.data!;

                        return ListView.separated(
                          itemCount: orders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final order = orders[index];
                            final items = allItems
                                .where((it) =>
                                    it['order_id'] == order['id'] &&
                                    it['status'] != 'cancelled')
                                .toList();
                            return _OrderPrintCard(
                              order: order,
                              items: items,
                              tableNumbers: tableNumbers,
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderPrintCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> tableNumbers;

  const _OrderPrintCard({
    required this.order,
    required this.items,
    required this.tableNumbers,
  });

  @override
  Widget build(BuildContext context) {
    final orderType = (order['order_type'] as String? ?? 'dine_in').toLowerCase();
    final isToGo = orderType == 'takeout' || orderType == 'to_go' || orderType == 'delivery';
    final foodAreaLabel = isToGo ? 'Para Llevar' : 'Cocina';

    final drinkItems = items.where((it) {
      final dish = it['dishes'] as Map<String, dynamic>?;
      return _isDrinkCategory(dish?['category'] as String?);
    }).toList();
    final foodItems = items.where((it) {
      final dish = it['dishes'] as Map<String, dynamic>?;
      return !_isDrinkCategory(dish?['category'] as String?);
    }).toList();

    bool? drinkStatus;
    if (drinkItems.isNotEmpty) {
      drinkStatus = drinkItems.every((it) => it['printed_at'] != null);
    }
    bool? foodStatus;
    if (foodItems.isNotEmpty) {
      foodStatus = foodItems.every((it) => it['printed_at'] != null);
    }

    String title;
    if (order['table_id'] != null) {
      final number = tableNumbers[order['table_id']];
      title = number != null ? 'Mesa $number' : 'Mesa';
    } else {
      final name = (order['customer_name'] as String?)?.trim();
      title = '${isToGo ? (orderType == 'delivery' ? 'Delivery' : 'To Go') : 'Orden'}'
          '${name != null && name.isNotEmpty ? ' — $name' : ''}';
    }
    if (order['daily_folio'] != null) {
      title += ' · Folio #${(order['daily_folio'] as num).toString().padLeft(3, '0')}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1DE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5DCC4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3D2E1A)),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 12),
          _PrintStatusChip(label: 'Bebidas', status: drinkStatus),
          const SizedBox(width: 8),
          _PrintStatusChip(label: foodAreaLabel, status: foodStatus),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.visibility_outlined, color: Color(0xFFFF6D00), size: 20),
            tooltip: 'Vista previa del ticket',
            onPressed: () => _showTicketPreview(
              context,
              order: order,
              foodItems: foodItems,
              drinkItems: drinkItems,
              foodAreaLabel: foodAreaLabel,
            ),
          ),
        ],
      ),
    );
  }
}

/// Info parseada de `customer_name` (mismo formato/regex que
/// parseCustomerName en print-worker/index.js): "Nombre (Pago: X) - DIR:
/// ... - TEL: ...".
class _CustomerInfo {
  final String name;
  final String? pago;
  final String? dir;
  final String? tel;
  const _CustomerInfo({required this.name, this.pago, this.dir, this.tel});
}

_CustomerInfo _parseCustomerName(String? raw) {
  if (raw == null || raw.isEmpty) return const _CustomerInfo(name: '');
  final nameMatch = RegExp(r'^([^()\-]+)').firstMatch(raw);
  final name = (nameMatch?.group(1) ?? raw).trim();
  final pago = RegExp(r'\(Pago:\s*([^)]+)\)', caseSensitive: false).firstMatch(raw)?.group(1)?.trim();
  final dir = RegExp(r'-\s*DIR:\s*([^-]+?)(?:\s*-\s*TEL:|$)', caseSensitive: false).firstMatch(raw)?.group(1)?.trim();
  final tel = RegExp(r'-\s*TEL:\s*(.+)$', caseSensitive: false).firstMatch(raw)?.group(1)?.trim();
  return _CustomerInfo(name: name, pago: pago, dir: dir, tel: tel);
}

List<String> _parseGuisadosPreview(dynamic raw) {
  if (raw == null) return const [];
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is List) {
      return decoded.whereType<String>().where((s) => s.isNotEmpty).toList();
    }
  } catch (_) {}
  return const [];
}

const _orderTypeLabels = {
  'dine_in': 'COMER AQUÍ',
  'to_go': 'TO GO',
  'takeout': 'TO GO',
  'delivery': 'A DOMICILIO',
};

/// Arma el texto del ticket simulado, con el mismo formato/orden de
/// secciones que appendTicket() en print-worker/index.js (encabezado,
/// tipo/fecha/cliente, items con sus extras, pie con folio corto) — para
/// que el mesero/cajero pueda ver cómo saldría SIN necesitar ninguna
/// Raspberry ni impresora física conectada.
String _buildTicketPreviewText({
  required String kind,
  required Map<String, dynamic> order,
  required List<Map<String, dynamic>> items,
}) {
  final buffer = StringBuffer();
  const width = 32;
  String center(String s) {
    final pad = ((width - s.length) / 2).floor();
    return pad > 0 ? '${' ' * pad}$s' : s;
  }
  final divider = '-' * width;

  buffer.writeln(center((order['branch_name'] as String?) ?? ''));
  buffer.writeln(center(kind));
  buffer.writeln(divider);

  final orderType = (order['order_type'] as String? ?? 'dine_in').toLowerCase();
  buffer.writeln('Tipo: ${_orderTypeLabels[orderType] ?? orderType.toUpperCase()}');
  final cust = _parseCustomerName(order['customer_name'] as String?);
  if (cust.name.isNotEmpty) buffer.writeln('Cliente: ${cust.name}');
  if (cust.tel != null && cust.tel!.isNotEmpty) buffer.writeln('Tel: ${cust.tel}');
  if (cust.dir != null && cust.dir!.isNotEmpty) {
    buffer.writeln('Direccion:');
    buffer.writeln('  ${cust.dir}');
  }
  buffer.writeln(divider);

  for (final it in items) {
    final dish = it['dishes'] as Map<String, dynamic>?;
    final rawName = (dish?['name'] as String?) ?? '(sin nombre)';
    final guisados = _parseGuisadosPreview(it['guisados_selected']);
    final name = _correctDrinkName(rawName, guisados);
    final qty = (it['quantity'] as num?)?.toInt() ?? 1;
    buffer.writeln('${qty}x $name');
    if (guisados.isNotEmpty) {
      buffer.writeln('   ${guisados.join(', ')}');
    }
  }
  buffer.writeln(divider);
  buffer.writeln(center(order['daily_folio'] != null
      ? 'Folio #${(order['daily_folio'] as num).toString().padLeft(3, '0')}'
      : 'ID: ${order['id'].toString().substring(0, 8)}'));
  return buffer.toString();
}

Future<void> _showTicketPreview(
  BuildContext context, {
  required Map<String, dynamic> order,
  required List<Map<String, dynamic>> foodItems,
  required List<Map<String, dynamic>> drinkItems,
  required String foodAreaLabel,
}) async {
  final sections = <(String, List<Map<String, dynamic>>)>[
    if (foodItems.isNotEmpty) (foodAreaLabel.toUpperCase(), foodItems),
    if (drinkItems.isNotEmpty) ('BEBIDAS', drinkItems),
  ];

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFFFAF1DE),
      title: const Row(
        children: [
          Icon(Icons.visibility_outlined, color: Color(0xFFFF6D00)),
          SizedBox(width: 8),
          Text('Vista previa (simulada)', style: TextStyle(color: Color(0xFF3D2E1A))),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sections.isEmpty)
                const Text('Esta orden no tiene items.', style: TextStyle(color: Colors.grey)),
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Icon(Icons.content_cut, size: 16, color: Color(0xFFA08F70)),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5DCC4)),
                  ),
                  child: Text(
                    _buildTicketPreviewText(
                      kind: sections[i].$1,
                      order: order,
                      items: sections[i].$2,
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Esta es una simulación dentro de la app — no imprime nada de verdad ni en ninguna Raspberry.',
                style: TextStyle(fontSize: 11, color: Color(0xFFA08F70)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
      ],
    ),
  );
}

/// status == null  → N/A (la orden no tiene items de esa área)
/// status == true   → ya se imprimió todo lo de esa área
/// status == false  → falta imprimir algo de esa área
class _PrintStatusChip extends StatelessWidget {
  final String label;
  final bool? status;

  const _PrintStatusChip({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String statusText;
    if (status == null) {
      color = const Color(0xFFB6A88A);
      icon = Icons.remove;
      statusText = 'N/A';
    } else if (status == true) {
      color = Colors.green;
      icon = Icons.check_circle;
      statusText = 'Impreso';
    } else {
      color = Colors.orange;
      icon = Icons.hourglass_bottom;
      statusText = 'Pendiente';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text('$label: $statusText',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// Fila de LEDs (uno por Raspberry esperada) — verde si mandó heartbeat
/// hace menos de _heartbeatStaleAfter, rojo si no. Se basa en
/// print_worker_heartbeats, que cada print-worker escribe cada ~20s
/// (ver print-worker/index.js, sendHeartbeat).
class PrinterLedsRow extends StatefulWidget {
  /// true → sin fondo/borde de tarjeta, para usarse pegada dentro de
  /// otra barra (ej. la barra fija de abajo en admin_view.dart).
  final bool compact;

  const PrinterLedsRow({super.key, this.compact = false});

  @override
  State<PrinterLedsRow> createState() => PrinterLedsRowState();
}

class PrinterLedsRowState extends State<PrinterLedsRow> {
  final _supabase = Supabase.instance.client;
  final _audioPlayer = AudioPlayer();
  Timer? _pollTimer;
  // null = todavía no sabemos (no avisar en la primera carga); true/false
  // = último estado conocido, para detectar CAMBIOS y avisar solo ahí.
  final Map<String, bool?> _lastKnownOnline = {};
  // Se guarda la sucursal con la que se armó el stream actual — si
  // Globals.currentBranch cambia (ej. todavía no había cargado la
  // guardada cuando este widget arrancó — arranca en 'Sucursal
  // Maravillas' por default hasta que termina esa carga async), hay que
  // volver a crear el stream con la sucursal correcta.
  String? _streamBranch;
  Stream<List<Map<String, dynamic>>>? _heartbeatStream;

  @override
  void initState() {
    super.initState();
    // El stream solo avisa cuando llega un heartbeat NUEVO — si una Pi se
    // cae, no hay ningún evento nuevo que dispare un rebuild y notemos
    // que ya pasaron los 45s. Revisamos cada 5s con la hora actual para
    // detectar la desconexión aunque no llegue ningún dato nuevo. De paso,
    // esto también hace que se reintente armar el stream con la sucursal
    // correcta una vez que Globals.currentBranch ya cargó de verdad.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  DateTime? _lastSeenFor(List<Map<String, dynamic>> rows, List<String> areas) {
    DateTime? latest;
    for (final row in rows) {
      if (!areas.contains(row['print_area'])) continue;
      final seen = DateTime.tryParse(row['last_seen_at'] as String? ?? '');
      if (seen != null && (latest == null || seen.isAfter(latest))) {
        latest = seen;
      }
    }
    return latest;
  }

  void _announceChange(String label, bool isOnline) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isOnline
            ? '🟢 $label volvió a conectarse'
            : '🔴 $label se desconectó'),
        backgroundColor: isOnline ? Colors.green[700] : Colors.red[700],
        duration: const Duration(seconds: 5),
      ),
    );
    if (!isOnline) {
      // Solo sonido en la desconexión — es lo que de verdad necesita
      // atención inmediata; la reconexión ya se resolvió sola.
      _audioPlayer.play(
        UrlSource('https://actions.google.com/sounds/v1/alarms/beep_short.ogg'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_streamBranch != Globals.currentBranch) {
      _streamBranch = Globals.currentBranch;
      _heartbeatStream = _supabase
          .from('print_worker_heartbeats')
          .stream(primaryKey: ['id'])
          .eq('branch_name', Globals.currentBranch);
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _heartbeatStream,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const [];
        final now = DateTime.now().toUtc();

        final ledRow = Wrap(
          spacing: 20,
          runSpacing: 10,
          children: _expectedPrintAreas.map((area) {
            final (matchAreas, label, icon) = area;
            final lastSeen = _lastSeenFor(rows, matchAreas);
            final isOnline = lastSeen != null &&
                now.difference(lastSeen) < _heartbeatStaleAfter;

            final previous = _lastKnownOnline[label];
            if (previous != null && previous != isOnline) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _announceChange(label, isOnline));
            }
            _lastKnownOnline[label] = isOnline;

            final color = isOnline ? Colors.green : Colors.redAccent;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 16, color: const Color(0xFF7A6E5A)),
                const SizedBox(width: 4),
                Text(label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3D2E1A))),
              ],
            );
          }).toList(),
        );

        if (widget.compact) return ledRow;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF1DE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5DCC4)),
          ),
          child: ledRow,
        );
      },
    );
  }
}
