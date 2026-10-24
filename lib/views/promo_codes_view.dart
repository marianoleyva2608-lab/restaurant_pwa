import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Creador de cupones de descuento (palabras). Cada cupón se puede usar una
/// sola vez por teléfono de cliente; en Caja se captura en Descuento → Cupón.
class PromoCodesView extends StatefulWidget {
  const PromoCodesView({super.key});

  @override
  State<PromoCodesView> createState() => _PromoCodesViewState();
}

class _PromoCodesViewState extends State<PromoCodesView> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _codes = [];
  Map<String, int> _uses = {};
  bool _loading = true;
  String? _error;

  static const _orange = Color(0xFFFF6D00);
  static const _brown = Color(0xFF3D2E1A);
  static const _grey = Color(0xFFA08F70);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final codes = await _supabase
          .from('promo_codes')
          .select('code, percent, active, expires_at, description, created_at')
          .order('created_at', ascending: false);
      final reds = await _supabase.from('promo_redemptions').select('code');
      final uses = <String, int>{};
      for (final r in reds as List) {
        final c = r['code'].toString();
        uses[c] = (uses[c] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        _codes = List<Map<String, dynamic>>.from(codes);
        _uses = uses;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los cupones. ¿Ya se crearon las tablas en Supabase?\n$e';
        _loading = false;
      });
    }
  }

  void _msg(String t, [Color c = Colors.green]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t), backgroundColor: c));
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _create() async {
    final codeCtrl = TextEditingController();
    final pctCtrl = TextEditingController(text: '20');
    final descCtrl = TextEditingController();
    DateTime? expires;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFFFAF1DE),
          title: const Text('Nuevo cupón',
              style: TextStyle(color: _orange, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Palabra del cupón',
                    hintText: 'Ej. NISSAN2024',
                    helperText: 'Letras y números, sin espacios',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pctCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Descuento', suffixText: '%'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      hintText: 'Ej. Convenio empleados Nissan'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expires == null
                            ? 'Sin fecha de vencimiento'
                            : 'Vence: ${_fmtDate(expires!)}',
                        style: const TextStyle(color: _brown),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.event, color: _orange),
                      label: const Text('Elegir', style: TextStyle(color: _orange)),
                      onPressed: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: now.add(const Duration(days: 30)),
                          firstDate: now,
                          lastDate: DateTime(now.year + 3),
                        );
                        if (d != null) setD(() => expires = d);
                      },
                    ),
                    if (expires != null)
                      IconButton(
                        tooltip: 'Quitar fecha',
                        icon: const Icon(Icons.close, color: _grey),
                        onPressed: () => setD(() => expires = null),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Cada cliente (por teléfono) lo puede usar una sola vez.',
                    style: TextStyle(color: _grey, fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar', style: TextStyle(color: _grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _orange, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final code = codeCtrl.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final pct = double.tryParse(pctCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (!RegExp(r'^[A-Z0-9_-]{3,30}$').hasMatch(code)) {
      _msg('La palabra debe tener de 3 a 30 letras o números, sin espacios', Colors.red);
      return;
    }
    if (pct <= 0 || pct > 100) {
      _msg('El descuento debe ser entre 1 y 100%', Colors.red);
      return;
    }
    try {
      await _supabase.from('promo_codes').insert({
        'code': code,
        'percent': pct,
        'active': true,
        'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        // Vence al final del día elegido.
        if (expires != null)
          'expires_at': DateTime(expires!.year, expires!.month, expires!.day, 23, 59, 59)
              .toUtc()
              .toIso8601String(),
      });
      _msg('Cupón $code creado');
      _load();
    } catch (e) {
      final dup = e.toString().contains('duplicate') || e.toString().contains('23505');
      _msg(dup ? 'Ya existe un cupón con la palabra $code' : 'No se pudo crear: $e',
          Colors.red);
    }
  }

  Future<void> _toggle(Map<String, dynamic> c, bool active) async {
    try {
      await _supabase
          .from('promo_codes')
          .update({'active': active}).eq('code', c['code']);
      _load();
    } catch (e) {
      _msg('No se pudo cambiar: $e', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF1DE),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo cupón'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _orange))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _codes.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text('Aún no hay cupones.\nToca "Nuevo cupón" para crear uno.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _grey)),
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                          itemCount: _codes.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final c = _codes[i];
                            final code = c['code'].toString();
                            final pct = (c['percent'] as num).toDouble();
                            final exp = DateTime.tryParse(c['expires_at']?.toString() ?? '')?.toLocal();
                            final vencido = exp != null && exp.isBefore(DateTime.now());
                            final active = c['active'] == true && !vencido;
                            final uses = _uses[code] ?? 0;
                            return Card(
                              color: Colors.white,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: active ? _orange : Colors.grey.shade400,
                                  foregroundColor: Colors.white,
                                  child: Text('${pct.toStringAsFixed(0)}%',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                ),
                                title: Text(code,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, color: _brown, letterSpacing: 1)),
                                subtitle: Text(
                                  [
                                    if ((c['description'] ?? '').toString().isNotEmpty) c['description'],
                                    'Usado $uses ${uses == 1 ? 'vez' : 'veces'}',
                                    exp == null
                                        ? 'Sin vencimiento'
                                        : (vencido ? 'Venció ${_fmtDate(exp)}' : 'Vence ${_fmtDate(exp)}'),
                                  ].join(' · '),
                                  style: const TextStyle(color: _grey),
                                ),
                                trailing: Switch(
                                  value: c['active'] == true,
                                  activeColor: _orange,
                                  onChanged: vencido ? null : (v) => _toggle(c, v),
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
