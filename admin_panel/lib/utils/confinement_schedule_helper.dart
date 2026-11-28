import 'package:intl/intl.dart';

/// Computes the 2-calendar-day Ante-Mortem confinement schedule (ending at
/// 8:00 AM opening time, e.g., Nov 28 -> Nov 30 at 8:00 AM) and provides
/// consistent display labels for Admin queues, dialogs, and customer alerts.
class ConfinementScheduleHelper {
  ConfinementScheduleHelper._();

  static const int defaultConfinementDays = 2;
  static const int openingHour = 8;

  static int resolveConfinementDays(Map<String, dynamic> req) {
    final instr = (req['special_instruction'] ?? '').toString();
    final m = RegExp(r'\[CONFINED_FROM:[^|\]]+\|days=(\d+)\]').firstMatch(instr);
    if (m != null) {
      final parsed = int.tryParse(m.group(1) ?? '');
      if (parsed != null && parsed >= 1 && parsed <= 14) {
        return parsed;
      }
    }
    final explicit = int.tryParse((req['confinement_days'] ?? '').toString());
    if (explicit != null && explicit >= 1 && explicit <= 14) {
      return explicit;
    }
    return defaultConfinementDays;
  }

  /// Resolves the local DateTime when the animal entered confinement.
  static DateTime resolveConfinementStart(Map<String, dynamic> req) {
    final candidates = [
      req['inspection_created_at'],
      req['updated_at'],
      req['created_at'],
    ];
    for (final raw in candidates) {
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }

  /// Ends [days] calendar days later at 8:00 AM opening time.
  /// Example: Nov 28, 2026 (any time) -> Nov 30, 2026 at 8:00 AM.
  static DateTime computeConfinementEnd(
    DateTime start, {
    int days = defaultConfinementDays,
  }) {
    final local = start.toLocal();
    return DateTime(local.year, local.month, local.day + days, openingHour, 0);
  }

  static DateTime resolveConfinementEnd(Map<String, dynamic> req) {
    final start = resolveConfinementStart(req);
    final days = resolveConfinementDays(req);
    return computeConfinementEnd(start, days: days);
  }

  static bool isConfinementEnded(Map<String, dynamic> req, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toLocal();
    final end = resolveConfinementEnd(req);
    return !current.isBefore(end);
  }

  static String formatStartLabel(DateTime start) {
    return DateFormat('MMM d, yyyy • h:mm a').format(start.toLocal());
  }

  static String formatEndLabel(DateTime end) {
    return DateFormat('MMM d, yyyy • h:mm a').format(end.toLocal());
  }

  static String formatShortEndLabel(DateTime end) {
    return DateFormat('MMM d, h:mm a').format(end.toLocal());
  }

  static String formatRemainingLabel(DateTime end, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toLocal();
    final diff = end.difference(current);
    if (diff.isNegative || diff.inMinutes <= 0) {
      return 'Confinement Ended — Ready to Evaluate';
    }
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final mins = diff.inMinutes % 60;
    if (days > 0) {
      return '${days}d ${hours}h left';
    }
    if (hours > 0) {
      return '${hours}h ${mins}m left';
    }
    return '${mins}m left';
  }
}
