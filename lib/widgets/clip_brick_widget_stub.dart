import 'package:flutter/material.dart';

/// Stub para builds non-web (APK Android). El brick de Clip sólo carga
/// como JS en navegador; en el APK no aplica porque el flujo de cliente
/// (checkout en línea) no se usa desde el mesero. Se renderiza un
/// placeholder para evitar errores de compilación.
class ClipBrickWidget extends StatelessWidget {
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
    
  }

  /// Cierra la verificación 3D Secure.
  static void hide3DS() {
    
  }

  static void showLoading([String msg = 'Procesando pago…']) {}

  static void hideLoading() {}

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF1DE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5DCC4)),
      ),
      child: const Text(
        'El pago en línea (Clip) sólo está disponible desde el sitio web.',
        style: TextStyle(color: Color(0xFFA08F70), fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}
