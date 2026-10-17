// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

// Llave PÚBLICA de producción de Clip (la secreta vive en Supabase,
// tabla app_config → clip_secret_key; nunca en la app).
const _clipApiKey = '25bc972c-6cea-4fb6-940d-53c5a8f0a5b1';

class ClipBrickWidget extends StatefulWidget {
  final double amount;
  final void Function(Map<String, dynamic> data) onSubmit;
  final void Function(String error)? onError;
  final void Function()? onReady;

  const ClipBrickWidget({
    super.key,
    required this.amount,
    required this.onSubmit,
    this.onError,
    this.onReady,
  });

  /// Muestra la verificación 3D Secure del banco (pantalla completa).
  static void show3DS(String url) {
    js.context.callMethod('clipShow3DS', [url]);
  }

  /// Cierra la verificación 3D Secure.
  static void hide3DS() {
    js.context.callMethod('clipHide3DS', []);
  }

  /// Círculo de carga a pantalla completa mientras se cobra.
  static void showLoading([String msg = 'Procesando pago…']) {
    js.context.callMethod('clipShowLoading', [msg]);
  }

  static void hideLoading() {
    js.context.callMethod('clipHideLoading', []);
  }

  @override
  State<ClipBrickWidget> createState() => _ClipBrickWidgetState();
}

class _ClipBrickWidgetState extends State<ClipBrickWidget> {
  late final String _viewId;
  late final String _containerId;
  bool _listo = false;

  @override
  void initState() {
    super.initState();
    final ts = DateTime.now().millisecondsSinceEpoch;
    _viewId = 'clip-brick-$ts';
    _containerId = 'clip-container-$ts';

    ui.platformViewRegistry.registerViewFactory(_viewId, (int id) {
      final div = html.DivElement()
        ..id = _containerId
        ..style.width = '100%'
        ..style.minHeight = '320px';
      return div;
    });

    js.context['_clipOnReady'] = () {
      if (mounted) setState(() => _listo = true);
      widget.onReady?.call();
    };

    js.context['_clipOnSubmit'] = (String rawData) {
      final data = jsonDecode(rawData) as Map<String, dynamic>;
      widget.onSubmit(data);
    };

    js.context['_clipOnError'] = (String rawError) {
      widget.onError?.call(rawError);
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      js.context.callMethod('clipInitBrick', [
        _containerId,
        _clipApiKey,
        widget.amount.toString(),
      ]);
    });
  }

  @override
  void dispose() {
    js.context.callMethod('clipUnmount', []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Incluye el espacio del botón "Pagar con tarjeta", que va dentro
        // del mismo recuadro, justo debajo de los datos de la tarjeta.
        SizedBox(
          height: 440,
          child: HtmlElementView(viewType: _viewId),
        ),
        const SizedBox(height: 8),
        if (!_listo)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text('Cargando pago con tarjeta…',
                  style: TextStyle(color: Color(0xFFA08F70), fontSize: 13)),
            ),
          )
      ],
    );
  }
}
