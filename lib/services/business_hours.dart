/// Horario de pedidos en línea: todos los días de 8:00 am a 2:00 pm,
/// hora del centro de México (UTC-6, sin horario de verano).
const int kOpenHour = 8;
const int kCloseHour = 14;

DateTime mexicoNow() => DateTime.now().toUtc().subtract(const Duration(hours: 6));

bool isOpenNow() {
  final h = mexicoNow().hour;
  return h >= kOpenHour && h < kCloseHour;
}

const String kHorarioTexto = 'Todos los días de 8:00 am a 2:00 pm';
