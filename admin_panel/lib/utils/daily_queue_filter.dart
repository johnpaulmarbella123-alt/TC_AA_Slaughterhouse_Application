/// Shared daily rollover filter for active operational workflow queues.
///
/// Never deletes records from Supabase — Reports & Records, Revenue, and Audit
/// Logs remain 100% intact. Simply hides concluded/completed transactions whose
/// completion timestamp occurred before today's local midnight so each morning
/// starts with a clean operational board while unfinished or overdue items
/// remain visible until completed.
class DailyQueueFilter {
  static DateTime get _todayMidnight {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Parses the first valid timestamp from [candidates] in local time and
  /// returns `true` if that calendar day is strictly before today.
  static bool isBeforeToday(List<dynamic> candidates) {
    final today = _todayMidnight;
    for (final raw in candidates) {
      if (raw == null) continue;
      final str = raw.toString().trim();
      if (str.isEmpty) continue;
      final dt = DateTime.tryParse(str)?.toLocal();
      if (dt != null) {
        final day = DateTime(dt.year, dt.month, dt.day);
        return day.isBefore(today);
      }
    }
    return false;
  }

  /// Returns `true` when [req] is already concluded for the current module AND
  /// was concluded on a previous calendar day (before today's local midnight).
  static bool shouldHideFromActiveQueue(
    Map<String, dynamic> req, {
    required Set<String> concludedStatuses,
    bool treatCompleteStageAsConcluded = false,
  }) {
    final status = (req['status'] ?? '').toString().trim().toLowerCase();
    final stage = (req['process_stage'] ?? '').toString().trim();
    final isConcluded = concludedStatuses.contains(status) ||
        (treatCompleteStageAsConcluded && stage == 'Complete');
    if (!isConcluded) return false;

    final payment = req['payment'] is Map ? req['payment'] as Map : null;
    final notesStr = (req['process_notes'] ?? '').toString();
    final completedTagMatch = RegExp(r'\[COMPLETED_AT:([^\]]+)\]').firstMatch(notesStr);
    final completedAtTag = completedTagMatch?.group(1)?.trim();

    return isBeforeToday([
      completedAtTag,
      req['released_at'],
      req['updated_at'],
      payment?['paid_at'],
      payment?['created_at'],
      req['inspection_created_at'],
      req['cancelled_at'],
      req['created_at'],
    ]);
  }
}
