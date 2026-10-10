// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

const _clipApiKey = 'test_81e93889-cfde-414a-8cf4-16cdc37f39bc';

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
        SizedBox(
          height: 360,
          child: HtmlElementView(viewType: _viewId),
        ),
        const SizedBox(height: 8),
        if (!_listo)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text('Cargando Clip…',
                  style: TextStyle(color: Color(0xFFA08F70), fontSize: 13)),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFC4C02).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: const Color(0xFFFC4C02).withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.arrow_downward, color: Color(0xFFFC4C02), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pulsa el botón naranja "Pagar con Clip" al pie de la pantalla',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFFFC4C02), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
