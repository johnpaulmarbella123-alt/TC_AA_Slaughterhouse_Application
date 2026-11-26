import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/animals_in_lot_editor.dart';

/// Centralized Ear-Tag exclusivity and lifecycle registry.
///
/// An Ear-Tag assigned to any livestock head remains exclusive to that animal
/// while its request is active on the abattoir floor, and becomes reusable only
/// once the request is Dispatched (`out_for_delivery`), Released (`released`),
/// Completed (`completed`), or concluded (`cancelled`, `rejected`, `taken_back`,
/// `condemned`).
class EarTagRegistryService {
  static const Set<String> reusableStatuses = {
    'released',
    'out_for_delivery',
    'completed',
    'cancelled',
    'rejected',
    'taken_back',
    'condemned',
  };

  /// Normalizes an ear-tag for case-insensitive comparison.
  static String normalize(String raw) => raw.trim().toUpperCase();

  /// Returns true if [raw] is a real user-entered ear-tag (not empty or legacy 'Auto #N').
  static bool isRealTag(String raw) {
    final clean = normalize(raw);
    if (clean.isEmpty) return false;
    return !RegExp(r'^AUTO\s*#?\d+$').hasMatch(clean);
  }

  /// Fetches all currently active (non-reusable) ear-tags from Supabase `requests`.
  ///
  /// Returns a map of `NORMALIZED_EAR_TAG -> "MI-YYYY-XXX (Customer Name)"`.
  /// Pass [excludeRequestId] when editing/approving an existing request so its
  /// own tags do not conflict with itself.
  static Future<Map<String, String>> fetchActiveEarTags(
    SupabaseClient supabase, {
    dynamic excludeRequestId,
  }) async {
    final activeMap = <String, String>{};
    final excludeStr = excludeRequestId?.toString().trim();

    try {
      final rows = await supabase
          .from('requests')
          .select('id, status, customer_name, animals_in_lot');

      final year = DateTime.now().year;
      for (final rawRow in (rows as List)) {
        if (rawRow is! Map) continue;
        final row = Map<String, dynamic>.from(rawRow);
        final rowIdStr = row['id']?.toString().trim() ?? '';
        if (excludeStr != null && excludeStr.isNotEmpty && rowIdStr == excludeStr) {
          continue;
        }

        final status = (row['status'] ?? '').toString().trim().toLowerCase();
        if (reusableStatuses.contains(status)) {
          continue;
        }

        final lotRaw = row['animals_in_lot'];
        if (lotRaw == null) continue;

        final items = AnimalLotItem.parseList(lotRaw, fallbackCount: 0);
        final refNo = 'MI-$year-${rowIdStr.padLeft(3, '0')}';
        final cust = (row['customer_name'] ?? 'Customer').toString().trim();
        final ownerLabel = cust.isNotEmpty ? '$refNo ($cust)' : refNo;

        for (final item in items) {
          final norm = normalize(item.earTag);
          if (isRealTag(norm)) {
            activeMap.putIfAbsent(norm, () => ownerLabel);
          }
        }
      }
    } catch (e) {
      debugPrint('EarTagRegistryService.fetchActiveEarTags error: $e');
    }

    return activeMap;
  }

  /// Validates every head in [items] against:
  /// 1. Mandatory non-empty requirement (if [requireEarTag] is true)
  /// 2. Duplicate ear-tags within the same lot
  /// 3. Active ear-tags currently assigned to other unreleased/undispatched requests
  ///
  /// Returns a map of `headIndex -> error message` (empty map means all valid).
  static Map<int, String> validateLot(
    List<AnimalLotItem> items,
    Map<String, String> activeTags, {
    bool requireEarTag = true,
  }) {
    final errors = <int, String>{};
    final seenInLot = <String, int>{}; // normalized tag -> first headIndex

    for (int i = 0; i < items.length; i++) {
      final norm = normalize(items[i].earTag);
      if (norm.isEmpty) {
        if (requireEarTag) {
          errors[i] = 'Ear-Tag # is required';
        }
        continue;
      }

      if (seenInLot.containsKey(norm)) {
        final firstIdx = seenInLot[norm]!;
        errors[i] = 'Duplicate Ear-Tag (already used on Head #${firstIdx + 1})';
        errors.putIfAbsent(
          firstIdx,
          () => 'Duplicate Ear-Tag (also used on Head #${i + 1})',
        );
        continue;
      }
      seenInLot[norm] = i;

      if (activeTags.containsKey(norm)) {
        errors[i] =
            'In use by ${activeTags[norm]} — reusable only after release/dispatch';
      }
    }

    return errors;
  }

  /// Performs a fresh database check right before saving or approving a lot.
  /// Returns a map of `headIndex -> error message` (empty map means safe to save).
  static Future<Map<int, String>> validateBeforeSave(
    SupabaseClient supabase,
    List<AnimalLotItem> items, {
    dynamic excludeRequestId,
    bool requireEarTag = true,
  }) async {
    final freshActive = await fetchActiveEarTags(
      supabase,
      excludeRequestId: excludeRequestId,
    );
    return validateLot(items, freshActive, requireEarTag: requireEarTag);
  }
}
