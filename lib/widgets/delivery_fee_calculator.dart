import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../globals.dart';
import '../services/delivery_fee.dart';
import '../services/geocoder.dart';
import '../services/google_distance.dart';
import '../services/holidays_mx.dart';
import '../services/weather.dart';

/// Widget compacto que calcula la cuota de delivery FLASH a partir de:
///  - km (input)
///  - km de carretera (opcional)
///  - toggles de lluvia / festivo
///
/// Llama [onChanged] cada vez que cambia el desglose, para que el
/// formulario padre sume la cuota al total de la orden.
class DeliveryFeeCalculator extends StatefulWidget {
  final String? destinationAddress;
  final ValueChanged<DeliveryFeeBreakdown> onChanged;

  /// Callback opcional cuando el usuario toca "Usar mi ubicación" y la
  /// app obtiene una dirección por reverse-geocode. El parent debería
  /// llenar su TextField de dirección con este texto.
  final ValueChanged<String>? onAddressDetected;

  /// Valores iniciales (al editar una orden ya creada).
  final double initialKm;
  final double initialKmCarretera;
  final bool initialRain;
  final bool initialHoliday;

  /// Si es false oculta el botón grande "Usar mi ubicación (GPS)" — útil
  /// cuando el parent ya lo expone en otro lado (p.ej. dentro del campo
  /// de dirección). El método [DeliveryFeeCalculatorState.useMyLocation]
  /// sigue siendo accesible vía GlobalKey.
  final bool showGpsButton;

  /// Modo cliente: oculta botones y campos de captura (Calcular km, Ver
  /// ruta, km, carretera, lluvia, festivo). Solo muestra la distancia y
  /// el desglose; lluvia y festivo se siguen detectando solos.
  final bool readOnly;

  const DeliveryFeeCalculator({
    super.key,
    required this.onChanged,
    this.destinationAddress,
    this.onAddressDetected,
    this.initialKm = 0,
    this.initialKmCarretera = 0,
    this.initialRain = false,
    this.initialHoliday = false,
    this.showGpsButton = true,
    this.readOnly = false,
  });

  @override
  State<DeliveryFeeCalculator> createState() => DeliveryFeeCalculatorState();
}

class DeliveryFeeCalculatorState extends State<DeliveryFeeCalculator> {
  late final TextEditingController _kmCtrl;
  late final TextEditingController _kmCarrCtrl;
  bool _rain = false;
  bool _holiday = false;
  bool _autoCalcLoading = false;
  String? _autoCalcError;
  String? _lastAutoCalcAddress;
  Timer? _autoCalcDebounce;

  @override
  void initState() {
    super.initState();
    _kmCtrl = TextEditingController(
        text: widget.initialKm > 0 ? widget.initialKm.toString() : '');
    _kmCarrCtrl = TextEditingController(
        text: widget.initialKmCarretera > 0
            ? widget.initialKmCarretera.toString()
            : '');
    _rain = widget.initialRain;
    // Si hoy cae en festivo del negocio, lo prendemos auto. Cuando
    // initialHoliday venía true (edición de orden), respetamos eso.
    _holiday = widget.initialHoliday || isHolidayToday();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
    // Si ya venía con dirección, calcula automático.
    _maybeAutoCalc(widget.destinationAddress);
    // Auto-detectar lluvia consultando Open-Meteo con las coords de
    // la sucursal. No bloquea el UI: el toggle se prende cuando
    // termina la consulta. Si initialRain venía true (edición de
    // orden), respetamos lo que el usuario ya había puesto.
    if (!widget.initialRain) _autoDetectRain();
  }

  Future<void> _autoDetectRain() async {
    final coords = kBranchCoords[Globals.currentBranch];
    if (coords == null) return;
    final raining = await isRainingNow(lat: coords.lat, lon: coords.lon);
    if (!mounted || !raining) return;
    setState(() {
      _rain = true;
      _emit();
    });
  }

  @override
  void didUpdateWidget(covariant DeliveryFeeCalculator old) {
    super.didUpdateWidget(old);
    if (old.destinationAddress != widget.destinationAddress) {
      _maybeAutoCalc(widget.destinationAddress);
    }
  }

  @override
  void dispose() {
    _autoCalcDebounce?.cancel();
    _kmCtrl.dispose();
    _kmCarrCtrl.dispose();
    super.dispose();
  }

  /// Dispara cálculo automático de km con debounce de 1.2 s para no
  /// pegarle a Nominatim mientras el usuario sigue tecleando.
  void _maybeAutoCalc(String? address) {
    _autoCalcDebounce?.cancel();
    final addr = (address ?? '').trim();
    if (addr.length < 8) return; // muy corto, no vale la pena
    if (addr == _lastAutoCalcAddress) return; // ya calculado
    _autoCalcDebounce = Timer(const Duration(milliseconds: 1200), () async {
      await _autoCalcKm(addr);
    });
  }

  Future<void> _autoCalcKm(String address) async {
    final coords = kBranchCoords[Globals.currentBranch];
    if (coords == null) return; // sucursal sin coords precalculadas
    if (mounted) {
      setState(() {
        _autoCalcLoading = true;
        _autoCalcError = null;
      });
    }

    // 1) Intentar Google Distance Matrix (distancia REAL por carretera)
    double? km = await googleDrivingDistanceKm(
      originLat: coords.lat,
      originLon: coords.lon,
      destinationAddress: address,
    );

    // 2) Fallback: OSM/Nominatim (haversine × 1.3)
    km ??= await kmFromBranchTo(
      branchLat: coords.lat,
      branchLon: coords.lon,
      destinationAddress: address,
    );

    if (!mounted) return;
    setState(() {
      _autoCalcLoading = false;
      _lastAutoCalcAddress = address;
      if (km == null) {
        _autoCalcError = 'No se pudo ubicar la dirección — teclea km manual';
      } else {
        _kmCtrl.text = km.toString();
        _autoCalcError = null;
        _emit();
      }
    });
  }

  void _emit() {
    final km = double.tryParse(_kmCtrl.text.replaceAll(',', '.')) ?? 0;
    final kmCarr =
        double.tryParse(_kmCarrCtrl.text.replaceAll(',', '.')) ?? 0;
    widget.onChanged(calculateDeliveryFee(
      km: km,
      kmCarretera: kmCarr,
      rain: _rain,
      holiday: _holiday,
    ));
  }

  /// Pide permiso de ubicación, obtiene GPS, calcula la distancia desde
  /// la sucursal y reverse-geocode para llenar el campo de dirección.
  /// Público para que un parent (p.ej. el botón dentro del campo de
  /// dirección) pueda dispararlo vía GlobalKey.
  Future<void> useMyLocation() => _useMyLocation();

  Future<void> _useMyLocation() async {
    final coords = kBranchCoords[Globals.currentBranch];
    if (coords == null) return;
    if (mounted) {
      setState(() {
        _autoCalcLoading = true;
        _autoCalcError = null;
      });
    }
    try {
      // 1) ¿Servicio de ubicación habilitado?
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw 'Activa el servicio de ubicación de tu dispositivo';
      }
      // 2) Permiso
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Necesitamos permiso de ubicación';
      }
      // 3) Posición
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));

      // 4) Distancia real por carretera desde la sucursal a estas coords
      final km = await googleDrivingDistanceKmCoords(
        originLat: coords.lat,
        originLon: coords.lon,
        destLat: pos.latitude,
        destLon: pos.longitude,
      );

      // 5) Dirección legible (reverse geocode): Google primero, Nominatim como fallback
      String? address = await googleReverseGeocode(
        lat: pos.latitude,
        lon: pos.longitude,
      );
      address ??= await nominatimReverseGeocode(
        lat: pos.latitude,
        lon: pos.longitude,
      );

      if (!mounted) return;
      // Llenar dirección SIEMPRE que la tengamos (independiente de si km calculó)
      if (address != null && widget.onAddressDetected != null) {
        widget.onAddressDetected!(address);
      }
      setState(() {
        _autoCalcLoading = false;
        if (km != null) {
          _kmCtrl.text = km.toString();
          _lastAutoCalcAddress = address;
          _autoCalcError = null;
          _emit();
        } else if (address != null) {
          // Dirección detectada pero sin km automático
          _autoCalcError = '📍 Dirección detectada. Ingresa los km manualmente.';
        } else {
          _autoCalcError = 'No se pudo detectar la dirección. Ingrésala manualmente.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _autoCalcLoading = false;
        _autoCalcError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _openMaps() async {
    final url = Uri.parse(buildMapsRouteUrl(
      branchName: Globals.currentBranch,
      destinationAddress: widget.destinationAddress,
    ));
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir Maps')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final km = double.tryParse(_kmCtrl.text.replaceAll(',', '.')) ?? 0;
    final kmCarr =
        double.tryParse(_kmCarrCtrl.text.replaceAll(',', '.')) ?? 0;
    final fee = calculateDeliveryFee(
      km: km,
      kmCarretera: kmCarr,
      rain: _rain,
      holiday: _holiday,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Botón grande GPS: queda arriba de todo (cuando aplica).
        if (widget.showGpsButton) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _autoCalcLoading ? null : _useMyLocation,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Usar mi ubicación (GPS)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF6D00),
                side:
                    const BorderSide(color: Color(0xFFFF6D00), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        // Título: "Cuota de Envío FLASH" ARRIBA del cuadro, centrado.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.delivery_dining,
                color: Color(0xFFFF6D00), size: 20),
            SizedBox(width: 6),
            Text(
              'Cuota de Envío FLASH',
              style: TextStyle(
                color: Color(0xFFFF6D00),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Acciones centradas: Calcular km · Ver ruta (entre título y caja).
        if (widget.readOnly && _autoCalcLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(6),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFFFF6D00)),
              ),
            ),
          ),
        if (!widget.readOnly) Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_autoCalcLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFFF6D00)),
                ),
              )
            else
              TextButton.icon(
                onPressed: () {
                  final addr = (widget.destinationAddress ?? '').trim();
                  if (addr.isNotEmpty) {
                    _lastAutoCalcAddress = null; // forzar
                    _autoCalcKm(addr);
                  }
                },
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('Calcular km'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6D00),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _openMaps,
              icon: const Icon(Icons.map, size: 16),
              label: const Text('Ver ruta'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF6D00),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Caja naranja con km inputs, chips lluvia/festivo, totales.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6D00).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFFFF6D00).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
          if (_autoCalcError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFB7472A).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFB7472A).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: Color(0xFFB7472A)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.readOnly
                            ? 'No pudimos ubicar tu dirección. Revísala; si es correcta, te confirmamos el costo de envío al llamarte.'
                            : 'No se ubicó la dirección. Tap "Ver ruta" para abrir Google Maps y teclea los km manualmente.',
                        style: const TextStyle(
                            color: Color(0xFFB7472A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (widget.readOnly)
            Text(
              'Distancia: ${_kmCtrl.text.isEmpty ? '—' : _kmCtrl.text} km',
              style: const TextStyle(
                  color: Color(0xFF3D2E1A), fontWeight: FontWeight.w600),
            ),
          if (!widget.readOnly) Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _kmCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(_emit),
                  style: const TextStyle(color: Color(0xFF3D2E1A)),
                  decoration: const InputDecoration(
                    labelText: 'Km totales',
                    labelStyle: TextStyle(color: Color(0xFFA08F70)),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _kmCarrCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(_emit),
                  style: const TextStyle(color: Color(0xFF3D2E1A)),
                  decoration: const InputDecoration(
                    labelText: 'Km de carretera',
                    labelStyle: TextStyle(color: Color(0xFFA08F70)),
                    isDense: true,
                    helperText: '+\$10 c/km',
                    helperStyle: TextStyle(
                        color: Color(0xFFA08F70), fontSize: 10),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!widget.readOnly) Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('🌧️ Lluvia (+\$20)'),
                selected: _rain,
                onSelected: (v) => setState(() {
                  _rain = v;
                  _emit();
                }),
                selectedColor:
                    const Color(0xFFFF6D00).withValues(alpha: 0.25),
                checkmarkColor: const Color(0xFFFF6D00),
                labelStyle: const TextStyle(color: Color(0xFF3D2E1A)),
              ),
              FilterChip(
                label: const Text('🎉 Festivo (+\$20)'),
                selected: _holiday,
                onSelected: (v) => setState(() {
                  _holiday = v;
                  _emit();
                }),
                selectedColor:
                    const Color(0xFFFF6D00).withValues(alpha: 0.25),
                checkmarkColor: const Color(0xFFFF6D00),
                labelStyle: const TextStyle(color: Color(0xFF3D2E1A)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE5DCC4)),
          const SizedBox(height: 8),
          if (fee.base > 0) ...[
            _line('Base por zona', fee.base),
            if (fee.extraKm > 0) _line('Km extra (>10)', fee.extraKm),
            if (fee.carretera > 0) _line('Carretera', fee.carretera),
            if (fee.rain > 0) _line('Lluvia', fee.rain),
            if (fee.holiday > 0) _line('Festivo', fee.holiday),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL ENVÍO',
                    style: TextStyle(
                      color: Color(0xFF3D2E1A),
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    )),
                Text('\$${fee.total.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFFFF6D00),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    )),
              ],
            ),
          ] else
            const Text(
              'Teclea los km para calcular el envío.',
              style: TextStyle(
                  color: Color(0xFFA08F70),
                  fontSize: 12,
                  fontStyle: FontStyle.italic),
            ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _line(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF7A6E5A), fontSize: 12)),
          Text('+\$${amount.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Color(0xFF7A6E5A),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
