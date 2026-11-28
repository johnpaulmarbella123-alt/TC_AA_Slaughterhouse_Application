import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../services/notification_service.dart';
import '../services/staff_notification_service.dart';
import '../services/inspection_documents_pdf_generator.dart';
import '../services/app_settings_service.dart';
import '../services/admin_realtime_hub.dart';
import '../services/audit_log_service.dart';
import '../services/regular_dealers_service.dart';
import '../services/walk_in_sms_service.dart';
import '../utils/text_capitalization_formatters.dart';
import '../utils/daily_queue_filter.dart';
import '../utils/confinement_schedule_helper.dart';
import '../utils/admin_responsive.dart';
import '../widgets/animals_in_lot_editor.dart';
import '../widgets/walk_in_sms_helper.dart';

class SlaughterInspectionPage extends StatefulWidget {
  final void Function(int moduleIndex, [String? tab])? onNavigate;
  const SlaughterInspectionPage({super.key, this.onNavigate});
  @override
  State<SlaughterInspectionPage> createState() => _SlaughterInspectionPageState();
}

class _SlaughterInspectionPageState extends State<SlaughterInspectionPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _allRequests = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _selectedBucketFilter = 'all'; // 'all', 'ante_mortem', 'slaughter_ops', 'post_mortem', 'weighing', 'completed', 'failed'
  String _typeFilter = 'all'; // 'all', 'barangay', 'market'
  Timer? _pollingTimer;
  Timer? _autoStageTicker;
  StreamSubscription<String>? _realtimeSub;
  final Set<String> _shownAnteMortemAlertIds = {};
  final Set<String> _updatingAutoStageIds = {};
  final Set<String> _autoFlaggingMissedIds = {};
  final ScrollController _tableScrollController = ScrollController();

  /// Returns true when a request is still Pending in Ante-Mortem past 5:00 PM
  /// on its scheduled `preferred_date` (and has not been rescheduled).
  static bool isPastMissedScheduleCutoff(Map<String, dynamic> req, {DateTime? nowOverride}) {
    final anti = (req['anti_mortem'] ?? 'Pending').toString();
    if (anti != 'Pending' && anti.isNotEmpty) return false;
    final status = (req['status'] ?? '').toString().toLowerCase();
    if (status != 'doc_verified') return false;
    if (req['rescheduled_date'] != null && req['rescheduled_date'].toString().trim().isNotEmpty) {
      return false;
    }
    final prefStr = req['preferred_date']?.toString();
    if (prefStr == null || prefStr.isEmpty) return false;
    final sched = DateTime.tryParse(prefStr);
    if (sched == null) return false;
    final now = nowOverride ?? DateTime.now();
    final cutoff = DateTime(sched.year, sched.month, sched.day, 17, 0); // 5:00 PM local time
    return !now.isBefore(cutoff);
  }
  Map<String, List<Map<String, dynamic>>> _walkInSmsRepliesByReqId = {};

  static const List<String> _autoSlaughterStages = [
    'Stunning',
    'Bleeding',
    'Scalding/Dehairing',
    'Evisceration',
  ];

  static DateTime? _extractAmPassedAt(Map<String, dynamic> req) {
    final direct = req['ante_mortem_passed_at']?.toString();
    if (direct != null && direct.isNotEmpty) {
      final parsed = DateTime.tryParse(direct);
      if (parsed != null) return parsed.toUtc();
    }
    final notes = (req['process_notes'] ?? '').toString();
    final m = RegExp(r'\[AM_PASSED_AT:([^\]]+)\]').firstMatch(notes);
    if (m != null && m.group(1) != null) {
      final parsed = DateTime.tryParse(m.group(1)!.trim());
      if (parsed != null) return parsed.toUtc();
    }
    final created = req['inspection_created_at']?.toString();
    if (created != null && created.isNotEmpty) {
      final parsed = DateTime.tryParse(created);
      if (parsed != null) return parsed.toUtc();
    }
    return null;
  }

  static bool _isEligibleForAutoSlaughter(Map<String, dynamic> req) {
    final anti = (req['anti_mortem'] ?? 'Pending').toString();
    if (anti != 'Passed') return false;
    final post = (req['post_mortem'] ?? 'Pending').toString().toUpperCase();
    if (post != 'PENDING' && post.isNotEmpty) return false;
    final status = (req['status'] ?? '').toString().toLowerCase();
    if ([
      'releasable',
      'mic_generated',
      'paid',
      'released',
      'completed',
      'anti_mortem_failed',
      'pickup_scheduled',
      'taken_back',
      'post_mortem_failed',
      'condemned',
      'delay_error',
    ].contains(status)) {
      return false;
    }
    final stage = (req['process_stage'] ?? '').toString();
    if ([
      'Post-Mortem Inspection',
      'Weighing',
      'Separate Facility (Weighing)',
      'Complete',
      'Condemned',
      'Technical Error/Delay',
    ].contains(stage)) {
      return false;
    }
    return true;
  }

  /// Returns `(targetStage, nextStageLabel, secondsRemainingToNext)` for an auto-advancing lot.
  static (String stage, String? nextStage, int secondsLeft) _computeAutoStageState(DateTime startUtc) {
    final elapsedSec = DateTime.now().toUtc().difference(startUtc).inSeconds;
    if (elapsedSec < 300) {
      return ('Stunning', 'Bleeding', (300 - elapsedSec).clamp(0, 300));
    } else if (elapsedSec < 600) {
      return ('Bleeding', 'Scalding/Dehairing', (600 - elapsedSec).clamp(0, 300));
    } else if (elapsedSec < 900) {
      return ('Scalding/Dehairing', 'Evisceration', (900 - elapsedSec).clamp(0, 300));
    }
    return ('Evisceration', null, 0);
  }

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _realtimeSub = AdminRealtimeHub.instance.listen(
      {'requests', 'slaughter_inspection', 'walkin_sms_replies'},
      () {
        if (mounted) {
          _loadRequests(silent: true);
          _checkAnteMortemAlerts();
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAnteMortemAlerts();
    });
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _loadRequests(silent: true);
        _checkAnteMortemAlerts();
      }
    });
    // Tick every 5 seconds to update live countdowns and auto-persist crossed 5-minute stages
    _autoStageTicker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) {
        _tickAutoSlaughterProgression();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _autoStageTicker?.cancel();
    _realtimeSub?.cancel();
    _searchController.dispose();
    _tableScrollController.dispose();
    super.dispose();
  }

  Future<void> _tickAutoSlaughterProgression() async {
    bool hasAnyActiveAuto = false;
    final List<Map<String, dynamic>> dueUpdates = [];

    for (final r in _allRequests) {
      if (!_isEligibleForAutoSlaughter(r)) continue;
      final startUtc = _extractAmPassedAt(r);
      if (startUtc == null) continue;

      final computed = _computeAutoStageState(startUtc);
      if (computed.$2 != null) {
        hasAnyActiveAuto = true;
      }
      final currentStageRaw = (r['process_stage'] ?? '').toString();
      final normalizedCurrent = currentStageRaw == 'Scalding/Plucking'
          ? 'Scalding/Dehairing'
          : currentStageRaw;

      // Only advance forward along the auto sequence, never backward if inspector advanced manually
      final curIdx = _autoSlaughterStages.indexOf(normalizedCurrent);
      final targetIdx = _autoSlaughterStages.indexOf(computed.$1);
      final shouldAdvance = (curIdx == -1 &&
              (normalizedCurrent.isEmpty ||
                  normalizedCurrent == 'Pending' ||
                  normalizedCurrent == 'Ante-Mortem' ||
                  normalizedCurrent == 'Anti-Mortem' ||
                  normalizedCurrent == 'Preparation')) ||
          (curIdx >= 0 && targetIdx > curIdx);

      if (shouldAdvance) {
        r['process_stage'] = computed.$1;
        hasAnyActiveAuto = true;
        final idKey = r['id']?.toString() ?? '';
        if (idKey.isNotEmpty && !_updatingAutoStageIds.contains(idKey)) {
          dueUpdates.add({'id': r['id'], 'idKey': idKey, 'stage': computed.$1});
        }
      }
    }

    if (hasAnyActiveAuto && mounted) {
      setState(() {});
    }

    for (final item in dueUpdates) {
      final idKey = item['idKey'] as String;
      _updatingAutoStageIds.add(idKey);
      try {
        await supabase
            .from('slaughter_inspection')
            .update({'process_stage': item['stage']})
            .eq('request_id', item['id']);
      } catch (e) {
        debugPrint('Auto-stage persist notice for req $idKey: $e');
      } finally {
        _updatingAutoStageIds.remove(idKey);
      }
    }
  }

  Future<void> _loadRequests({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      if (AppSettingsService.instance.hasActiveStaffSession ||
          supabase.auth.currentSession == null) {
        await AppSettingsService.instance.ensureAdminAuthSession();
      }
      await RegularDealersService.instance.init();
      // Fetch requests that are past Document Verification (doc_verified) or in slaughter phases.
      final data = await supabase
          .from('requests')
          .select('*, slaughter_inspection(*)')
          .inFilter('status', ['doc_verified', 'slaughter_started', 'releasable', 'delay_error', 'completed', 'anti_mortem_failed', 'pickup_scheduled', 'taken_back', 'post_mortem_failed', 'condemned', 'mic_generated'])
          .order('created_at', ascending: false);

      // Seamlessly sync response from system_settings ante_mortem_alerts & pickup_penalty_tracking
      Map<String, dynamic> alerts = {};
      Map<String, dynamic> trackingMap = {};
      try {
        final settingsRows = await supabase
            .from('system_settings')
            .select('key, value')
            .inFilter('key', ['ante_mortem_alerts', 'pickup_penalty_tracking']);
        for (final row in List<Map<String, dynamic>>.from(settingsRows)) {
          if (row['key'] == 'ante_mortem_alerts' && row['value'] is Map) {
            alerts = Map<String, dynamic>.from(row['value']);
          } else if (row['key'] == 'pickup_penalty_tracking' && row['value'] is Map) {
            trackingMap = Map<String, dynamic>.from(row['value']);
          }
        }
      } catch (_) {}
      
      final activeRequests = List<Map<String, dynamic>>.from(data).map((r) {
        final idStr = r['id'].toString();
        if (alerts.containsKey(idStr) && alerts[idStr] is Map) {
          final alertChoice = alerts[idStr]['choice']?.toString();
          if (alertChoice != null && alertChoice.isNotEmpty) {
            if (r['anti_mortem_response'] == null || r['anti_mortem_response'].toString().isEmpty) {
              r['anti_mortem_response'] = alertChoice;
              r['anti_mortem_response_at'] = alerts[idStr]['responded_at'];
              supabase.from('requests').update({
                'anti_mortem_response': alertChoice,
                'anti_mortem_response_at': alerts[idStr]['responded_at'] ?? DateTime.now().toIso8601String(),
              }).eq('id', r['id']).then((_) {}).catchError((_) {});
            }
          }
        }

        final inspectionList = r['slaughter_inspection'];
        Map<String, dynamic>? inspection;
        if (inspectionList is List && inspectionList.isNotEmpty) {
          inspection = inspectionList.first as Map<String, dynamic>;
        } else if (inspectionList is Map) {
          inspection = inspectionList as Map<String, dynamic>;
        }
        
        if (inspection != null) {
          r['anti_mortem'] = inspection['anti_mortem'];
          r['process_stage'] = inspection['process_stage'];
          r['post_mortem'] = inspection['post_mortem'];
          r['carcass_weight'] = inspection['carcass_weight'];
          r['inspector_name'] = inspection['inspector_name'];
          r['process_notes'] = inspection['process_notes'];
          r['condemnation_reason'] = inspection['condemnation_reason'];
          r['veterinary_findings'] = inspection['veterinary_findings'];
          r['inspection_created_at'] = inspection['created_at'];
          r['ante_mortem_passed_at'] = inspection['ante_mortem_passed_at'];
          r['passed_count'] = inspection['passed_count'] ?? r['passed_count'];
          r['condemned_count'] = inspection['condemned_count'] ?? r['condemned_count'];
        }
        // Enforce Ante-Mortem stage while ante-mortem inspection is still pending
        final rawAm = (r['anti_mortem'] ?? 'Pending').toString();
        final rawStage = (r['process_stage'] ?? '').toString();
        if ((rawAm.isEmpty || rawAm == 'Pending') &&
            (rawStage.isEmpty || rawStage == 'Pending' || rawStage == 'Preparation')) {
          r['process_stage'] = 'Ante-Mortem';
        }
        if (r['passed_count'] == null || r['condemned_count'] == null) {
          final notesStr = (r['process_notes'] ?? '').toString();
          final partialMatch = RegExp(
            r'\[PARTIAL BATCH:\s*(\d+)\s*Passed,\s*(\d+)\s*Condemned\]',
            caseSensitive: false,
          ).firstMatch(notesStr);
          if (partialMatch != null) {
            r['passed_count'] = int.tryParse(partialMatch.group(1) ?? '');
            r['condemned_count'] = int.tryParse(partialMatch.group(2) ?? '');
          }
        }
        if (trackingMap.containsKey(idStr) && trackingMap[idStr] is Map) {
          final t = trackingMap[idStr] as Map;
          r['penalty_fee'] = t['penalty_fee'];
          r['penalty_reason'] = t['penalty_reason'];
          r['actual_date'] = t['actual_date'];
          r['is_warning_only'] = t['is_warning_only'];
          r['offense_level'] = t['offense_level'];
        }
        return r;
      }).toList();
      
      // Fetch incoming walk-in SMS replies grouped by request_id (graceful if migration not yet run)
      final Map<String, List<Map<String, dynamic>>> repliesByReq = {};
      try {
        final repliesRows = await supabase
            .from('walkin_sms_replies')
            .select()
            .order('received_at', ascending: false)
            .limit(300);
        for (final row in List<Map<String, dynamic>>.from(repliesRows)) {
          final rid = row['request_id']?.toString();
          if (rid == null || rid.isEmpty) continue;
          repliesByReq.putIfAbsent(rid, () => []).add(row);
        }
      } catch (_) {}

      final visibleRequests = activeRequests
          .where(
            (r) => !DailyQueueFilter.shouldHideFromActiveQueue(
              r,
              concludedStatuses: const {
                'releasable',
                'mic_generated',
                'paid',
                'released',
                'completed',
                'condemned',
                'post_mortem_failed',
                'taken_back',
              },
              treatCompleteStageAsConcluded: true,
            ),
          )
          .toList();

      if (mounted) {
        setState(() {
          _allRequests = visibleRequests;
          _walkInSmsRepliesByReqId = repliesByReq;
          _isLoading = false;
        });
        _tickAutoSlaughterProgression();
        _autoEvaluateMissedSchedules(visibleRequests, trackingMap);
        _notifyEndedConfinements(visibleRequests);
      }
    } catch (e) {
      debugPrint('SlaughterInspection load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Sends a deduplicated Inspector staff bell alert once a confined animal's
  /// 2-calendar-day observation period has ended (8:00 AM opening time).
  Future<void> _notifyEndedConfinements(List<Map<String, dynamic>> requests) async {
    for (final r in requests) {
      final status = (r['status'] ?? '').toString().toLowerCase();
      final am = (r['anti_mortem'] ?? '').toString();
      if (status != 'anti_mortem_failed' && am != 'Failed') continue;
      if (!ConfinementScheduleHelper.isConfinementEnded(r)) continue;
      final reqId = (r['id'] is num) ? (r['id'] as num).toInt() : int.tryParse('${r['id']}');
      if (reqId == null) continue;
      final refNo = _refNo(r);
      final customer = (r['customer_name'] ?? 'Customer').toString();
      final livestock = (r['livestock_type'] ?? 'Livestock').toString();
      await StaffNotificationService.sendStaffNotification(
        targetRole: 'Inspector',
        type: 'confinement_ended',
        title: '2-Day Confinement Ended — Evaluate $refNo',
        message:
            '$refNo ($customer • $livestock) has completed its 2-day confinement. Please evaluate and notify the customer whether to continue slaughter or condemn.',
        requestId: reqId,
        referenceNo: refNo,
        dedupKey: 'req_${reqId}_confinement_ended',
      );
    }
  }

  /// Automatically flags Pending Ante-Mortem requests past 5:00 PM on their
  /// scheduled date so inspectors never have to manually press a Missed Schedule checkbox.
  Future<void> _autoEvaluateMissedSchedules(
    List<Map<String, dynamic>> requests,
    Map<String, dynamic> existingTrackingMap,
  ) async {
    final List<Map<String, dynamic>> overdue = [];
    for (final r in requests) {
      final idStr = r['id']?.toString() ?? '';
      if (idStr.isEmpty) continue;
      if (_autoFlaggingMissedIds.contains(idStr)) continue;
      if (existingTrackingMap.containsKey(idStr)) continue;
      if (r['penalty_reason'] != null || r['is_warning_only'] == true) continue;
      if (!isPastMissedScheduleCutoff(r)) continue;
      overdue.add(r);
    }
    if (overdue.isEmpty) return;

    for (final r in overdue) {
      _autoFlaggingMissedIds.add(r['id'].toString());
    }

    try {
      // Load latest tracking + customer missed history once for the batch
      Map<String, dynamic> trackMap = Map<String, dynamic>.from(existingTrackingMap);
      Map<String, dynamic> allHist = {};
      try {
        final rows = await supabase
            .from('system_settings')
            .select('key, value')
            .inFilter('key', ['pickup_penalty_tracking', 'customer_missed_schedule_history']);
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          if (row['key'] == 'pickup_penalty_tracking' && row['value'] is Map) {
            trackMap = Map<String, dynamic>.from(row['value']);
          } else if (row['key'] == 'customer_missed_schedule_history' && row['value'] is Map) {
            allHist = Map<String, dynamic>.from(row['value']);
          }
        }
      } catch (_) {}

      final nowStr = DateTime.now().toLocal().toIso8601String().split('T')[0];
      bool changed = false;

      for (final r in overdue) {
        final reqId = r['id'];
        final idStr = reqId.toString();
        if (trackMap.containsKey(idStr)) continue;

        final customerKey = (r['user_id'] ?? r['contact_number'] ?? r['customer_name'] ?? '')
            .toString()
            .trim();
        final cEntry = customerKey.isNotEmpty && allHist[customerKey] is Map
            ? Map<String, dynamic>.from(allHist[customerKey] as Map)
            : <String, dynamic>{};
        final recordsList = List<Map<String, dynamic>>.from((cEntry['records'] as List?) ?? []);
        final priorCount = recordsList
            .where((rec) => rec['request_id']?.toString() != idStr)
            .length;
        final isRepeatOffense = priorCount >= 1;
        final offenseLevel = isRepeatOffense ? (priorCount + 1) : 1;
        final double penaltyFee = isRepeatOffense ? 500.0 : 0.0;
        final penaltyReason = isRepeatOffense
            ? 'Auto Missed Schedule past 5:00 PM (Repeat #$offenseLevel — ₱500 Penalty)'
            : 'Auto Missed Schedule past 5:00 PM (1st Offense — Warning)';

        trackMap[idStr] = {
          'penalty_fee': penaltyFee,
          'penalty_reason': penaltyReason,
          'is_warning_only': !isRepeatOffense,
          'offense_level': offenseLevel,
          'actual_date': nowStr,
          'auto_flagged_at': DateTime.now().toIso8601String(),
        };

        final refNum = _refNo(r);
        recordsList.removeWhere((rec) => rec['request_id']?.toString() == idStr);
        recordsList.add({
          'request_id': reqId,
          'reference_no': refNum,
          'scheduled_date': r['preferred_date'],
          'actual_date': nowStr,
          'offense_level': offenseLevel,
          'action': isRepeatOffense ? 'penalty_charged' : 'warning_issued',
          'penalty_fee': penaltyFee,
          'auto_flagged': true,
          'recorded_at': DateTime.now().toIso8601String(),
        });
        cEntry['count'] = recordsList.length;
        cEntry['records'] = recordsList;
        if (customerKey.isNotEmpty) {
          allHist[customerKey] = cEntry;
        }

        // Update in-memory row immediately
        r['penalty_fee'] = penaltyFee;
        r['penalty_reason'] = penaltyReason;
        r['is_warning_only'] = !isRepeatOffense;
        r['offense_level'] = offenseLevel;
        r['actual_date'] = nowStr;
        changed = true;

        // Notify customer once
        final userId = r['user_id']?.toString();
        if (userId != null && userId.isNotEmpty) {
          final prefStr = r['preferred_date']?.toString() ?? 'scheduled date';
          String schedDisplay = prefStr;
          try {
            schedDisplay = DateFormat('MMMM d, yyyy').format(DateTime.parse(prefStr));
          } catch (_) {}
          if (!isRepeatOffense) {
            await NotificationService.sendNotificationSafely(
              supabase,
              userId: userId,
              title: '⚠️ Schedule Notice: 1st Offense Warning (Fee Waived)',
              message:
                  'Your livestock for $refNum did not arrive for ante-mortem inspection before the 5:00 PM cutoff on $schedDisplay. Under Tabaco City abattoir guidelines, grace is granted for your 1st offense (₱0.00 penalty). Repeat missed schedules will automatically incur a ₱500.00 Wasted Slot Penalty.',
              type: 'missed_schedule_warning',
              referenceNo: refNum,
              data: {
                'request_id': reqId,
                'reference_no': refNum,
                'offense_level': 1,
                'penalty_fee': 0.0,
                'is_warning_only': true,
                'scheduled_date': prefStr,
                'actual_date': nowStr,
                'auto_flagged': true,
              },
            );
          } else {
            await NotificationService.sendNotificationSafely(
              supabase,
              userId: userId,
              title: '⛔ Missed Schedule Penalty Applied (₱500.00)',
              message:
                  'Your livestock for $refNum did not arrive for ante-mortem inspection before the 5:00 PM cutoff on $schedDisplay. Having previously received a formal warning, an automatic ₱500.00 Wasted Slot Penalty has been added to your bill (Repeat Offense #$offenseLevel).',
              type: 'missed_schedule_penalty',
              referenceNo: refNum,
              data: {
                'request_id': reqId,
                'reference_no': refNum,
                'offense_level': offenseLevel,
                'penalty_fee': 500.0,
                'is_warning_only': false,
                'scheduled_date': prefStr,
                'actual_date': nowStr,
                'auto_flagged': true,
              },
            );
          }
        }
      }

      if (changed) {
        await supabase.from('system_settings').upsert({
          'key': 'pickup_penalty_tracking',
          'value': trackMap,
        });
        await supabase.from('system_settings').upsert({
          'key': 'customer_missed_schedule_history',
          'value': allHist,
        });
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Auto missed-schedule evaluation error: $e');
    } finally {
      for (final r in overdue) {
        _autoFlaggingMissedIds.remove(r['id'].toString());
      }
    }
  }

  String _refNo(Map<String, dynamic> req) =>
      'MI-${DateTime.now().year}-${req['id'].toString().padLeft(3, '0')}';

  String _formatDate(dynamic v) {
    if (v == null) return '—';
    try {
      return DateFormat('M/d/yyyy').format(DateTime.parse(v.toString()));
    } catch (_) {
      return v.toString();
    }
  }

  /// Classifies each request into one of the 6 top tracker stages:
  /// `'ante_mortem'`, `'slaughter_ops'`, `'post_mortem'`, `'weighing'`, `'completed'`, `'failed'`
  String _stageBucket(Map<String, dynamic> r) {
    final status = (r['status'] ?? '').toString().toLowerCase();
    final anti = (r['anti_mortem'] ?? 'Pending').toString();
    final post = (r['post_mortem'] ?? 'Pending').toString();
    final stageRaw = (r['process_stage'] ?? 'Ante-Mortem').toString();
    final stage = stageRaw == 'Scalding/Plucking' ? 'Scalding/Dehairing' : stageRaw;
    final weight = double.tryParse((r['carcass_weight'] ?? '').toString());

    // 1. Failed / Condemned (Ante-Mortem OR Whole Post-Mortem)
    // Note: 'Partially Condemned' proceeds to Weighing / Completed (healthy carcass parts are dispatched).
    if (status == 'anti_mortem_failed' ||
        status == 'pickup_scheduled' ||
        status == 'taken_back' ||
        status == 'post_mortem_failed' ||
        status == 'condemned' ||
        anti == 'Failed' ||
        post == 'Failed' ||
        stage == 'Condemned') {
      return 'failed';
    }

    // 2. Completed
    if (stage == 'Complete' ||
        ['releasable', 'mic_generated', 'paid', 'released', 'completed'].contains(status)) {
      return 'completed';
    }

    // 3. Separate Facility or Post-Mortem Passed / Partially Condemned awaiting weight -> Weighing
    if (stage == 'Weighing' ||
        stage == 'Separate Facility (Weighing)' ||
        anti == 'Separate Facility' ||
        ((post == 'Passed' || post == 'Partially Condemned') && (weight == null || weight <= 0))) {
      return 'weighing';
    }

    // 4. Ante-Mortem still pending
    if (anti.isEmpty || anti == 'Pending' || stage == 'Ante-Mortem' || stage == 'Anti-Mortem') {
      return 'ante_mortem';
    }

    // 5. Reached Evisceration or Post-Mortem Inspection -> Post-Mortem
    if (stage == 'Evisceration' || stage == 'Post-Mortem Inspection') {
      return 'post_mortem';
    }

    // 6. Active floor slaughter operations (Preparation, Stunning, Bleeding, Scalding/Dehairing, Delay)
    return 'slaughter_ops';
  }

  List<Map<String, dynamic>> _filteredList(List<Map<String, dynamic>> list) {
    final q = _searchController.text.toLowerCase().trim();
    return list.where((r) {
      final name = (r['customer_name'] ?? '').toString().toLowerCase();
      final ref = _refNo(r).toLowerCase();
      final reqType = (r['request_type'] ?? 'barangay').toString().toLowerCase();

      final matchesSearch = q.isEmpty || name.contains(q) || ref.contains(q);
      final matchesType = _typeFilter == 'all' || reqType == _typeFilter;
      final matchesBucket = _selectedBucketFilter == 'all' ||
          _stageBucket(r) == _selectedBucketFilter;

      return matchesSearch && matchesType && matchesBucket;
    }).toList();
  }

  void _openUpdateDialog(Map<String, dynamic> request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateProcessDialog(
        request: request,
        supabase: supabase,
        onDone: _loadRequests,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F)))
                : RefreshIndicator(
                    onRefresh: _loadRequests,
                    color: const Color(0xFF2D6A4F),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: AdminResponsive.pagePadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFilterRow(),
                          const SizedBox(height: 20),
                          _buildStatsCards(),
                          const SizedBox(height: 16),
                          _buildStageFilterButtons(),
                          const SizedBox(height: 16),
                          _buildTableCard(
                            title: 'Slaughter & Inspection Records',
                            subtitle: 'Unified barangay and market workflow — ante-mortem inspection, automated 5-minute slaughter stages, post-mortem, weighing, and MIC generation',
                            requests: _filteredList(_allRequests),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    Widget buildTypeChip(String key, String label) {
      final selected = _typeFilter == key;
      return InkWell(
        onTap: () => setState(() => _typeFilter = key),
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? const Color(0xFF0F5132) : const Color(0xFF64748B),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Search (Compact 260px width, 36px height)
        SizedBox(
          width: 260,
          height: 36,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13),
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search reference # or customer...',
              hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFFA0AEC0), size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 36),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF0F5132), width: 1.4),
              ),
            ),
          ),
        ),
        // Unified Category Quick Filter (All | Barangay | Market)
        Container(
          height: 36,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF2F7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildTypeChip('all', 'All Types'),
              buildTypeChip('barangay', 'Barangay'),
              buildTypeChip('market', 'Market'),
            ],
          ),
        ),
        if (_selectedBucketFilter != 'all' || _typeFilter != 'all' || _searchController.text.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedBucketFilter = 'all';
                _typeFilter = 'all';
                _searchController.clear();
              });
            },
            icon: const Icon(Icons.restart_alt, size: 16, color: Color(0xFF475569)),
            label: const Text('Reset Filters', style: TextStyle(fontSize: 12.5, color: Color(0xFF475569))),
          ),
      ],
    );
  }

  Widget _buildStatsCards() {
    int inProcess = 0, complete = 0, micGen = 0, total = 0;
    for (final r in _allRequests) {
      total++;
      final stage = r['process_stage']?.toString() ?? '';
      if (stage == 'Complete') {
        complete++;
      } else {
        inProcess++;
      }
      if ((r['status'] ?? '') == 'mic_generated' ||
          (r['process_notes']?.toString().contains('MIC Generated') ?? false) ||
          r['status'] == 'paid' ||
          r['status'] == 'released') {
        micGen++;
      }
    }

    return AdminResponsive.kpiGrid([
      _statCard('In Process', inProcess.toString(), Colors.blue),
      _statCard('Complete', complete.toString(), Colors.green),
      _statCard('MIC Generated', micGen.toString(), Colors.green, icon: Icons.check_circle_outline),
      _statCard('Today\'s Total', total.toString(), Colors.orange),
    ], spacing: 12);
  }

  Widget _statCard(String label, String value, Color accent, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                if (icon != null)
                  Icon(icon, size: 16, color: accent)
                else
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          ],
        ),
    );
  }

  Widget _buildStageFilterButtons() {
    int anteCount = 0;
    int opsCount = 0;
    int postCount = 0;
    int weighCount = 0;
    int compCount = 0;
    int failCount = 0;

    for (final r in _allRequests) {
      switch (_stageBucket(r)) {
        case 'ante_mortem':
          anteCount++;
          break;
        case 'slaughter_ops':
          opsCount++;
          break;
        case 'post_mortem':
          postCount++;
          break;
        case 'weighing':
          weighCount++;
          break;
        case 'completed':
          compCount++;
          break;
        case 'failed':
          failCount++;
          break;
      }
    }

    final buttons = [
      (key: 'all', label: 'All', count: _allRequests.length, accent: const Color(0xFF0F5132)),
      (key: 'ante_mortem', label: 'Ante-Mortem', count: anteCount, accent: const Color(0xFF2563EB)),
      (key: 'slaughter_ops', label: 'Slaughter Ops', count: opsCount, accent: const Color(0xFFD97706)),
      (key: 'post_mortem', label: 'Post-Mortem', count: postCount, accent: const Color(0xFF0D9488)),
      (key: 'weighing', label: 'Weighing', count: weighCount, accent: const Color(0xFF7C3AED)),
      (key: 'completed', label: 'Completed', count: compCount, accent: const Color(0xFF16A34A)),
      (key: 'failed', label: 'Failed', count: failCount, accent: const Color(0xFFDC2626)),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: buttons.map((b) {
        final isSelected = _selectedBucketFilter == b.key;
        return InkWell(
          onTap: () {
            setState(() {
              _selectedBucketFilter = (isSelected && b.key != 'all') ? 'all' : b.key;
            });
          },
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected ? b.accent : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? b.accent : const Color(0xFFE2E8F0),
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: b.accent.withValues(alpha: 0.22),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  b.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.22)
                        : (b.count > 0
                            ? b.accent.withValues(alpha: 0.12)
                            : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    b.count.toString(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Colors.white
                          : (b.count > 0 ? b.accent : const Color(0xFF94A3B8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTableCard({required String title, required String subtitle, required List<Map<String, dynamic>> requests}) {
    final scrollController = _tableScrollController;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3748))),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final bool showActionsColumn = _selectedBucketFilter != 'completed';
              final availableWidth = constraints.maxWidth;
              final tableWidth = math.max(showActionsColumn ? 1150.0 : 1020.0, availableWidth);
              final colSpacing = (availableWidth > 1400)
                  ? 34.0
                  : (availableWidth > 1100 ? 24.0 : 16.0);

              return Scrollbar(
                controller: scrollController,
                thumbVisibility: false,
                trackVisibility: false,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableWidth),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF7FAFC)),
                        dataRowMinHeight: 60,
                        dataRowMaxHeight: 80,
                        columnSpacing: colSpacing,
                columns: [
                  const DataColumn(label: Text('Reference #', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  const DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  const DataColumn(label: Text('Livestock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  const DataColumn(label: Text('Schedule/\nActual', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  const DataColumn(label: Text('Process Stage', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  const DataColumn(label: Text('Post-Mortem', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  const DataColumn(label: Text('Customer\nResponse', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  const DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  const DataColumn(label: Text('MIC', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  if (showActionsColumn)
                    const DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                ],
                rows: requests.map((req) {
                  final ref = _refNo(req);
                  final rawStage = (req['process_stage'] ?? 'Ante-Mortem').toString();
                  final stage = rawStage == 'Scalding/Plucking' ? 'Scalding/Dehairing' : rawStage;
                  final antiMortem = (req['anti_mortem'] ?? 'Pending').toString();
                  final postMortem = req['post_mortem'] ?? 'PENDING';
                  final status = req['status'] ?? '';
                  final isMarketRow = (req['request_type'] ?? '').toString().toLowerCase() == 'market';
                  final isDelayed = status == 'delay_error';
                  final isAntiMortemFailed = status == 'anti_mortem_failed' || status == 'pickup_scheduled' || status == 'taken_back';
                  final isPostMortemFailed = status == 'post_mortem_failed';
                  final isCondemnedStatus = status == 'condemned';
                  final isCondemned = req['condemnation_reason'] != null || isCondemnedStatus;
                  final isCondemnationAcknowledged = req['condemnation_acknowledged'] == true || isCondemnedStatus;
                  final customerResponse = req['anti_mortem_response']?.toString();
                  final isSeparateFacility = (antiMortem == 'Separate Facility') ||
                      stage.contains('Separate Facility') ||
                      (req['process_notes']?.toString().contains('SEPARATE FACILITY') ?? false);
                  final statusLower = status.toString().toLowerCase();
                  final bool isInspectionDone = stage == 'Complete' ||
                      [
                        'releasable',
                        'mic_generated',
                        'paid',
                        'released',
                        'completed',
                        'condemned',
                        'post_mortem_failed',
                        'taken_back',
                      ].contains(statusLower);
                  final bool isUnstarted = (antiMortem.isEmpty || antiMortem == 'Pending') &&
                      !isSeparateFacility &&
                      !isAntiMortemFailed &&
                      !isPostMortemFailed &&
                      !isCondemnedStatus &&
                      !isInspectionDone;

                  String? autoCountdownLabel;
                  if (_isEligibleForAutoSlaughter(req)) {
                    final startUtc = _extractAmPassedAt(req);
                    if (startUtc != null) {
                      final comp = _computeAutoStageState(startUtc);
                      if (comp.$2 != null) {
                        final mins = comp.$3 ~/ 60;
                        final secs = comp.$3 % 60;
                        autoCountdownLabel =
                            'Auto → ${comp.$2} in ${mins}m ${secs.toString().padLeft(2, '0')}s';
                      } else if (stage == 'Evisceration') {
                        autoCountdownLabel = 'Ready for Post-Mortem';
                      }
                    }
                  }

                  bool isScheduledForFutureDate() {
                    final pref = req['preferred_date']?.toString();
                    if (pref == null || pref.isEmpty) return false;
                    try {
                      final date = DateTime.parse(pref);
                      final today = DateTime.now();
                      final todayMidnight = DateTime(today.year, today.month, today.day);
                      final reqMidnight = DateTime(date.year, date.month, date.day);
                      return reqMidnight.isAfter(todayMidnight);
                    } catch (_) {
                      return false;
                    }
                  }
                  final bool isFuture = isScheduledForFutureDate();

                  return DataRow(cells: [
                    DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12))),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                req['customer_name']?.toString() ?? '—',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: isMarketRow ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isMarketRow ? const Color(0xFFBFDBFE) : const Color(0xFFA7F3D0),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                isMarketRow ? 'Market' : 'Barangay',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isMarketRow ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
                                ),
                              ),
                            ),
                          ],
                        ),
                        _buildSpecialInstructionBadge(
                          context,
                          req['special_instruction']?.toString(),
                          customerName: req['customer_name']?.toString(),
                          refNo: ref,
                        ),
                      ],
                    )),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${req['animal_count']} head(s) • ${req['livestock_type'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        if (req['condemned_count'] != null &&
                            (req['condemned_count'] as num) > 0 &&
                            req['passed_count'] != null &&
                            (req['passed_count'] as num) > 0) ...[
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFFDBA74), width: 0.8),
                            ),
                            child: Text(
                              '✓ ${req['passed_count']} Passed • ⚠ ${req['condemned_count']} Condemned',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFC2410C)),
                            ),
                          ),
                        ],
                        const SizedBox(height: 3),
                        if (req['marking'] != null && req['marking'].toString().trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF81C784), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.label_outline, size: 11, color: Color(0xFF2E7D32)),
                                const SizedBox(width: 3),
                                Text(
                                  'Tag: ${req['marking']}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                                ),
                              ],
                            ),
                          )
                        else
                          Text('No tag', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                      ],
                    )),
                    DataCell(() {
                      final scheduleDate = _formatDate(req['preferred_date']);
                      final rescheduledDate = req['rescheduled_date'];
                      if (rescheduledDate != null) {
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(scheduleDate, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, decoration: TextDecoration.lineThrough, color: Colors.grey.shade400)),
                            Text('New: ${_formatDate(rescheduledDate)}', style: TextStyle(fontSize: 11, color: Colors.blue.shade600, fontWeight: FontWeight.w500)),
                          ],
                        );
                      }
                      if (isDelayed) {
                        // If delayed due to a technical error, the actual date recorded
                        // is the date the processing actually took place (today or the recorded delay date),
                        // not the scheduled date shifted forward.
                        DateTime actualDate = DateTime.now();
                        if (req['actual_date'] != null) {
                          actualDate = DateTime.tryParse(req['actual_date'].toString())?.toLocal() ?? actualDate;
                        } else {
                          final match = RegExp(r'Technical delay \((\d{4}-\d{2}-\d{2})\)').firstMatch(req['process_notes']?.toString() ?? '');
                          if (match != null) {
                            actualDate = DateTime.tryParse(match.group(1)!) ?? actualDate;
                          } else if (req['inspection_created_at'] != null) {
                            actualDate = DateTime.tryParse(req['inspection_created_at'].toString())?.toLocal() ?? actualDate;
                          }
                        }
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(scheduleDate, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            Text('Actual: ${_formatDate(actualDate.toIso8601String())}', style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.w500)),
                          ],
                        );
                      }
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(scheduleDate, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          Text('Actual: $scheduleDate', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      );
                    }()),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBadge(
                          stage,
                          stage == 'Complete'
                              ? Colors.green
                              : (stage.contains('Separate Facility')
                                  ? const Color(0xFFC2410C)
                                  : ((stage == 'Ante-Mortem' || stage == 'Anti-Mortem')
                                      ? const Color(0xFF2563EB)
                                      : (_autoSlaughterStages.contains(stage)
                                          ? const Color(0xFFD97706)
                                          : Colors.blueGrey))),
                        ),
                        if (autoCountdownLabel != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            autoCountdownLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: stage == 'Evisceration'
                                  ? const Color(0xFF0D9488)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ],
                        if (isSeparateFacility && !stage.contains('Separate Facility')) ...[
                          const SizedBox(height: 2),
                          const Text(
                            '⚡ Separate Facility',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFC2410C)),
                          ),
                        ],
                      ],
                    )),
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (postMortem.toString().toUpperCase() == 'PARTIALLY CONDEMNED') ...[
                          _buildBadge('PARTIAL CONDEMN', const Color(0xFFD97706), light: true),
                          const SizedBox(height: 2),
                          const Text(
                            'Part Condemned • Carcass Passed',
                            style: TextStyle(fontSize: 9.5, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
                          ),
                        ] else ...[
                          _buildBadge(
                            postMortem.toString().toUpperCase(),
                            postMortem.toString().toUpperCase() == 'PASSED'
                                ? Colors.grey
                                : (postMortem.toString().toUpperCase() == 'FAILED' ? Colors.red : Colors.grey),
                            outline: true,
                          ),
                          if (isCondemned) const Text('Condemned!', style: TextStyle(fontSize: 10, color: Colors.red)),
                        ],
                      ],
                    )),
                    // Customer Response column
                    DataCell(
                      (isAntiMortemFailed &&
                              (req['special_instruction'] ?? '').toString().contains('[CONFINED_FROM:'))
                          ? Builder(builder: (_) {
                              final instr = (req['special_instruction'] ?? '').toString();
                              final m = RegExp(r'\[CONFINED_FROM:([^|\]]+)(?:\|days=(\d+))?\]').firstMatch(instr);
                              final parentRef = m?.group(1) ?? '';
                              final days = m?.group(2) ?? '1-2';
                              final headCount = req['animal_count'] ?? 1;
                              return GestureDetector(
                                onTap: () => _showClearConfinementDialog(req),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildBadge(
                                      customerResponse == 'confine'
                                          ? 'Confine ($headCount head • ${days}d)'
                                          : 'Awaiting Confine ($headCount • ${days}d)',
                                      customerResponse == 'confine' ? Colors.blue : Colors.orange,
                                      light: true,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      parentRef.isNotEmpty ? 'From $parentRef • Tap to manage' : 'Tap to manage',
                                      style: TextStyle(fontSize: 9, color: Colors.blue.shade400),
                                    ),
                                  ],
                                ),
                              );
                            })
                          : ((req['user_id'] ?? '').toString().trim().isEmpty ||
                                  (req['special_instruction'] ?? '').toString().contains('[WALK_IN]') ||
                                  (req['contact_number'] ?? '').toString().trim().isNotEmpty)
                              ? _buildWalkInCustomerResponseCell(
                                  req,
                                  isAntiMortemFailed: isAntiMortemFailed,
                                  isPostMortemFailed: isPostMortemFailed || isCondemnedStatus,
                                )
                              : (isPostMortemFailed || isCondemnedStatus)
                          ? (isCondemnationAcknowledged
                              ? _buildBadge('Slip Received & Concluded', Colors.green, light: true)
                              : _buildBadge('Awaiting Slip Review', Colors.orange, light: true))
                              : ((req['anti_mortem']?.toString() == 'Failed') &&
                                  req['condemned_count'] != null &&
                                  (req['condemned_count'] as num) > 0 &&
                                  req['passed_count'] != null &&
                                  (req['passed_count'] as num) > 0)
                              ? GestureDetector(
                                  onTap: () => _showClearConfinementDialog(req),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildBadge(
                                        customerResponse == 'confine'
                                            ? 'Confine (${req['condemned_count']} head)'
                                            : 'Awaiting Confine (${req['condemned_count']})',
                                        customerResponse == 'confine' ? Colors.blue : Colors.orange,
                                        light: true,
                                      ),
                                      const SizedBox(height: 2),
                                      Text('Tap to manage', style: TextStyle(fontSize: 9, color: Colors.blue.shade400)),
                                    ],
                                  ),
                                )
                              : isAntiMortemFailed
                              ? Builder(builder: (_) {
                                  final confEnd = ConfinementScheduleHelper.resolveConfinementEnd(req);
                                  final isEnded = ConfinementScheduleHelper.isConfinementEnded(req);
                                  final endShort = ConfinementScheduleHelper.formatShortEndLabel(confEnd);
                                  final remaining = ConfinementScheduleHelper.formatRemainingLabel(confEnd);
                                  return GestureDetector(
                                    onTap: () => _showClearConfinementDialog(req),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        _buildBadge(
                                          isEnded
                                              ? 'Confinement Ended'
                                              : 'Ends $endShort',
                                          isEnded ? Colors.green : Colors.blue,
                                          light: true,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isEnded
                                              ? 'Ready to evaluate'
                                              : '$remaining • Tap to view',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: isEnded ? FontWeight.w700 : FontWeight.w500,
                                            color: isEnded ? const Color(0xFF15803D) : Colors.blue.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                })
                              : isDelayed
                                  ? (customerResponse == null
                                      ? _buildBadge('Awaiting Fee Response', Colors.orange, light: true)
                                      : customerResponse == 'accept_penalty'
                                          ? GestureDetector(
                                              onTap: () => _openAntiMortemResponseDialog(req),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  _buildBadge('Fee Accepted (₱500)', Colors.green, light: true),
                                                  const SizedBox(height: 2),
                                                  Text('Tap to manage', style: TextStyle(fontSize: 9, color: Colors.green.shade600)),
                                                ],
                                              ),
                                            )
                                          : GestureDetector(
                                              onTap: () => _openAntiMortemResponseDialog(req),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  _buildBadge('Take Back', Colors.deepOrange, light: true),
                                                  const SizedBox(height: 2),
                                                  if (req['pickup_approved'] == true)
                                                    _buildBadge('Approved', Colors.green, light: true)
                                                  else
                                                    Text('Tap to approve', style: TextStyle(fontSize: 9, color: Colors.deepOrange.shade400)),
                                                ],
                                              ),
                                            ))
                                  : const Text('—', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                    DataCell(
                      isCondemnedStatus
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blueGrey.shade300),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline, color: Colors.blueGrey.shade700, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Operation Concluded',
                                    style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade800, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            )
                          : isAntiMortemFailed
                              ? _buildAntiMortemStatusBadge(req, status, customerResponse)
                              : isPostMortemFailed
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 16),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.red.shade200),
                                              ),
                                              child: Text(
                                                'Post-Mortem Failed',
                                                style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                              : isDelayed
                                  ? Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 16),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.orange.shade200),
                                              ),
                                              child: Text(
                                                'Facility Technical Delay',
                                                style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Facility Delay (₱0 Penalty)',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    )
                                  : (req['is_warning_only'] == true ||
                                          (req['penalty_fee'] == 0.0 && req['penalty_reason'] != null) ||
                                          (req['process_notes'] ?? '').toString().contains('1ST OFFENSE'))
                                      ? Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 15),
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.shade50,
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: Colors.amber.shade300),
                                                  ),
                                                  child: Text(
                                                    '1st Offense Warning',
                                                    style: TextStyle(fontSize: 10, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Fee Waived (₱0.00)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.amber.shade900,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        )
                                  : (req['penalty_fee'] != null && (double.tryParse(req['penalty_fee'].toString()) ?? 0.0) > 0)
                                      ? Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.event_busy, color: Colors.red.shade600, size: 15),
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.shade50,
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: Colors.red.shade200),
                                                  ),
                                                  child: Text(
                                                    'Repeat Slot Penalty',
                                                    style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Wasted Slot Fee: ₱${req['penalty_fee']}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.red.shade700,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        )
                                  : isFuture && status == 'doc_verified'
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEDE9FE),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFDDD6FE)),
                                          ),
                                          child: const Text(
                                            'AWAITING ARRIVAL',
                                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                                          ),
                                        )
                                      : _buildBadge(status == 'releasable' ? 'Releasable' : (status == 'mic_generated' ? 'MIC Generated' : (status == 'doc_verified' ? 'SLAUGHTER' : status.toUpperCase())), (status == 'releasable' || status == 'mic_generated') ? Colors.green : Colors.orange, light: true),
                    ),
                    DataCell(
                      (isPostMortemFailed || isCondemnedStatus || postMortem.toString().toUpperCase() == 'FAILED' || isAntiMortemFailed)
                          ? _buildBadge('Failed', Colors.red, light: true)
                          : (status == 'mic_generated' || (req['process_notes']?.toString().contains('MIC Generated') ?? false) || status == 'paid' || status == 'released')
                              ? OutlinedButton.icon(
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => _MICDialog(
                                      request: req,
                                      supabase: supabase,
                                      onDone: _loadRequests,
                                    ),
                                  ),
                                  icon: const Icon(Icons.print, size: 14, color: Color(0xFF2D6A4F)),
                                  label: const Text('Printed / View', style: TextStyle(fontSize: 11, color: Color(0xFF2D6A4F), fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.green.shade600),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                    minimumSize: const Size(0, 28),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                )
                              : status == 'releasable'
                                  ? ElevatedButton.icon(
                                      onPressed: () => showDialog(
                                        context: context,
                                        builder: (_) => _MICDialog(
                                          request: req,
                                          supabase: supabase,
                                          onDone: _loadRequests,
                                        ),
                                      ),
                                      icon: const Icon(Icons.download, size: 14, color: Colors.white),
                                      label: const Text('Generate', style: TextStyle(fontSize: 11, color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade600,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                        minimumSize: const Size(0, 28),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      ),
                                    )
                                  : _buildBadge('Pending', Colors.blue, light: true),
                    ),
                    if (showActionsColumn)
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          isFuture && status == 'doc_verified'
                              ? Tooltip(
                                  message: 'Livestock scheduled for a future date. Ante-mortem inspection cannot be logged until animal arrives at the facility.',
                                  child: OutlinedButton(
                                    onPressed: null,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      minimumSize: const Size(0, 32),
                                      side: BorderSide(color: Colors.grey.shade300),
                                      disabledForegroundColor: Colors.grey.shade400,
                                    ),
                                    child: const Text('Pending Arrival', style: TextStyle(fontSize: 11.5)),
                                  ),
                                )
                              : isUnstarted
                                  ? ElevatedButton.icon(
                                      onPressed: () => _openUpdateDialog(req),
                                      icon: const Icon(Icons.assignment_outlined, size: 14, color: Colors.white),
                                      label: const Text(
                                        'Open Inspection',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0F5132),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 11),
                                        minimumSize: const Size(0, 32),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                    )
                                  : isInspectionDone
                                      ? const SizedBox.shrink()
                                      : OutlinedButton(
                                          onPressed: () => _openUpdateDialog(req),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            minimumSize: const Size(0, 32),
                                            side: BorderSide(color: Colors.grey.shade300),
                                          ),
                                          child: const Text('Update', style: TextStyle(fontSize: 12, color: Color(0xFF4A5568))),
                                        ),
                          if (isPostMortemFailed || isCondemnedStatus || isCondemned) ...[
                            const SizedBox(width: 6),
                            Builder(
                              builder: (_) {
                                final rawReason = req['condemnation_reason']?.toString() ?? '';
                                final isPartialSlip = rawReason.contains('[Partial Condemnation') ||
                                    postMortem.toString().toUpperCase() == 'PARTIALLY CONDEMNED';
                                final slipMatch = RegExp(r'Slip:\s*([^|\]]+)').firstMatch(rawReason);
                                final wtMatch = RegExp(r'Weight:\s*([0-9.]+)').firstMatch(rawReason);
                                return OutlinedButton(
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => _CondemnationSlipDialog(
                                      request: req,
                                      condemnationReason: rawReason.isNotEmpty
                                          ? rawReason
                                          : 'Condemned after post-mortem inspection',
                                      inspectorName: req['inspector_name']?.toString() ?? 'Meat Inspector',
                                      carcassWeight: isPartialSlip && wtMatch != null
                                          ? (wtMatch.group(1) ?? '')
                                          : (req['carcass_weight']?.toString() ?? ''),
                                      supabase: supabase,
                                      isPartialCondemnation: isPartialSlip,
                                      slipNumber: slipMatch?.group(1)?.trim(),
                                      onDone: _loadRequests,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    minimumSize: const Size(0, 32),
                                    side: BorderSide(
                                      color: isPartialSlip ? Colors.orange.shade400 : Colors.red.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    isPartialSlip ? 'Partial Slip' : 'Slip',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isPartialSlip ? Colors.orange.shade800 : Colors.red.shade700,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                          if (isAntiMortemFailed && statusLower != 'taken_back') ...[
                            const SizedBox(width: 6),
                            Builder(builder: (_) {
                              final isEnded = ConfinementScheduleHelper.isConfinementEnded(req);
                              return ElevatedButton.icon(
                                icon: Icon(
                                  isEnded ? Icons.fact_check_outlined : Icons.schedule_outlined,
                                  size: 13,
                                ),
                                onPressed: () => _showClearConfinementDialog(req),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isEnded
                                      ? const Color(0xFF1E855A)
                                      : const Color(0xFF1E40AF),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  minimumSize: const Size(0, 32),
                                ),
                                label: Text(
                                  isEnded ? 'Evaluate Confinement' : 'Confinement Info',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              );
                            }),
                          ] else if (isDelayed) ...[
                            const SizedBox(width: 6),
                            if (status == 'pickup_scheduled')
                              ElevatedButton.icon(
                                icon: const Icon(Icons.handshake_outlined, size: 13),
                                onPressed: () => _showConfirmTakenBackDialog(req),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFC0392B),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: const Size(0, 32),
                                ),
                                label: const Text('Confirm Handover', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              )
                            else
                              OutlinedButton(
                                onPressed: () => _openAntiMortemResponseDialog(req),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  minimumSize: const Size(0, 32),
                                  side: BorderSide(color: Colors.blue.shade300),
                                ),
                                child: Text(
                                  customerResponse != null ? 'Respond' : 'Record Decision',
                                  style: TextStyle(fontSize: 12, color: Colors.blue.shade600),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ]);
                }).toList(),
              ),
              ),
            ),
            ),
          );
        },
      ),
        ],
      ),
    );
  }

  Widget _buildSpecialInstructionBadge(BuildContext context, String? instruction, {String? customerName, String? refNo}) {
    if (instruction == null || instruction.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final text = instruction.trim();

    return Tooltip(
      message: 'Customer Special Note: $text\n(Click to view details)',
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
      ),
      child: InkWell(
        onTap: () => _showSpecialInstructionDialog(context, text, customerName: customerName, refNo: refNo),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_outlined, size: 12, color: Color(0xFFB45309)),
              SizedBox(width: 4),
              Text(
                'Special Note',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB45309),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpecialInstructionDialog(BuildContext context, String text, {String? customerName, String? refNo}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.assignment_outlined, color: Color(0xFFB45309), size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Customer Special Instructions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (refNo != null || customerName != null) ...[
              Row(
                children: [
                  if (refNo != null)
                    Text(refNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF2D6A4F))),
                  if (refNo != null && customerName != null)
                    const Text(' • ', style: TextStyle(color: Colors.grey)),
                  if (customerName != null)
                    Text(customerName, style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568), fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                text,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF78350F), height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D6A4F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openAntiMortemResponseDialog(Map<String, dynamic> request) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AntiMortemResponseDialog(
        request: request,
        supabase: supabase,
        onDone: _loadRequests,
      ),
    );
  }

  Future<void> _acknowledgeAnteMortemAlert(String reqId) async {
    try {
      final alertRow = await supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'ante_mortem_alerts')
          .maybeSingle();
      if (alertRow != null && alertRow['value'] is Map) {
        final alerts = Map<String, dynamic>.from(alertRow['value']);
        if (alerts.containsKey(reqId) && alerts[reqId] is Map) {
          alerts[reqId]['acknowledged'] = true;
          await supabase.from('system_settings').upsert({
            'key': 'ante_mortem_alerts',
            'value': alerts,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _checkAnteMortemAlerts() async {
    try {
      // 1. Check system_settings ante_mortem_alerts for instant notifications
      try {
        final alertRow = await supabase
            .from('system_settings')
            .select('value')
            .eq('key', 'ante_mortem_alerts')
            .maybeSingle();
        if (alertRow != null && alertRow['value'] is Map) {
          final alerts = Map<String, dynamic>.from(alertRow['value']);
          for (final entry in alerts.entries) {
            final idStr = entry.key;
            final alert = entry.value as Map<String, dynamic>;
            if (alert['acknowledged'] == true) continue;
            if (_shownAnteMortemAlertIds.contains(idStr)) continue;

            final req = _allRequests.firstWhere(
              (r) => r['id'].toString() == idStr,
              orElse: () => <String, dynamic>{},
            );
            if (req.isNotEmpty) {
              _shownAnteMortemAlertIds.add(idStr);
              if (mounted) {
                _showAnteMortemAlertModal(req, alert['choice']?.toString() ?? 'accept_penalty');
              }
              return;
            }
          }
        }
      } catch (_) {}

      // 2. Direct requests table query fallback
      final data = await supabase
          .from('requests')
          .select('id, customer_name, livestock_type, animal_count, status, anti_mortem_response, anti_mortem_response_at')
          .inFilter('status', ['anti_mortem_failed', 'delay_error'])
          .not('anti_mortem_response', 'is', null)
          .order('anti_mortem_response_at', ascending: false)
          .limit(5);

      for (final req in data) {
        final idStr = req['id'].toString();
        final response = req['anti_mortem_response']?.toString();
        if (response != null && response.isNotEmpty && !_shownAnteMortemAlertIds.contains(idStr)) {
          _shownAnteMortemAlertIds.add(idStr);
          if (mounted) {
            _showAnteMortemAlertModal(req, response);
          }
          break;
        }
      }
    } catch (_) {}
  }

  void _showAnteMortemAlertModal(Map<String, dynamic> req, String choice) {
    final ref = _refNo(req);
    final customer = req['customer_name'] ?? 'Customer';
    final livestock = req['livestock_type'] ?? 'Livestock';
    final count = req['animal_count'] ?? 1;
    final isPenaltyAccepted = choice == 'accept_penalty';
    final isConfine = choice == 'confine';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isPenaltyAccepted
                  ? Icons.receipt_long
                  : (isConfine ? Icons.medical_services_outlined : Icons.assignment_return_outlined),
              color: isPenaltyAccepted
                  ? const Color(0xFF16A34A)
                  : (isConfine ? const Color(0xFFD97706) : const Color(0xFFC0392B)),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isPenaltyAccepted
                    ? 'Technical Delay: Reschedule Accepted'
                    : 'Ante-Mortem Decision Received',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isPenaltyAccepted
                      ? const Color(0xFFECFDF5)
                      : (isConfine ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isPenaltyAccepted
                        ? const Color(0xFFA7F3D0)
                        : (isConfine ? const Color(0xFFFCD34D) : const Color(0xFFFCA5A5)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order: $ref | $customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('Livestock: $livestock ($count head)', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Customer Response: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Expanded(
                          child: Text(
                            isPenaltyAccepted
                                ? 'ACCEPTED ₱500 PENALTY & RESCHEDULE'
                                : (isConfine ? 'CONFINE IN SLAUGHTERHOUSE' : 'TAKE LIVESTOCK BACK'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isPenaltyAccepted
                                  ? const Color(0xFF15803D)
                                  : (isConfine ? const Color(0xFFB45309) : const Color(0xFFDC2626)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!isPenaltyAccepted && isConfine) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.event_available_outlined, size: 14, color: Color(0xFF92400E)),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '2-Day Confinement Ends: ${ConfinementScheduleHelper.formatEndLabel(ConfinementScheduleHelper.resolveConfinementEnd(req))}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isPenaltyAccepted
                    ? 'The customer accepted the ₱500 legal finality fee to keep livestock in the facility for resumed slaughter. Please select the rescheduled date.'
                    : (isConfine
                        ? 'The animal will remain under 2-day observation until ${ConfinementScheduleHelper.formatEndLabel(ConfinementScheduleHelper.resolveConfinementEnd(req))}. Once confinement ends, evaluate whether to continue slaughter or condemn and notify the customer.'
                        : 'The customer chose to retrieve their livestock. Please set the pickup schedule so the customer knows when to collect the animal at the corral.'),
                style: const TextStyle(fontSize: 13, color: Color(0xFF4A5568)),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _acknowledgeAnteMortemAlert(req['id'].toString());
            },
            child: const Text('Dismiss'),
          ),
          ElevatedButton.icon(
            icon: Icon(
              isPenaltyAccepted
                  ? Icons.calendar_month
                  : (isConfine ? Icons.check : Icons.schedule),
              size: 16,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _acknowledgeAnteMortemAlert(req['id'].toString());
              if (isPenaltyAccepted) {
                _openAntiMortemResponseDialog(req);
              } else if (isConfine) {
                _showClearConfinementDialog(req);
              } else {
                _openAntiMortemResponseDialog(req);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isPenaltyAccepted
                  ? const Color(0xFF2563EB)
                  : (isConfine ? const Color(0xFF1E855A) : const Color(0xFFC0392B)),
              foregroundColor: Colors.white,
            ),
            label: Text(
              isPenaltyAccepted
                  ? 'Set Rescheduled Date'
                  : (isConfine ? 'Manage Confinement' : 'Set Pickup Schedule'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalkInCustomerResponseCell(
    Map<String, dynamic> req, {
    required bool isAntiMortemFailed,
    required bool isPostMortemFailed,
  }) {
    final reqIdStr = req['id']?.toString() ?? '';
    final replies = _walkInSmsRepliesByReqId[reqIdStr] ?? const [];
    final hasReplies = replies.isNotEmpty;
    final latest = hasReplies ? replies.first : null;
    final latestMsg = (latest?['message'] ?? '').toString().trim();
    final parsedAction = (latest?['parsed_action'] ?? 'reply').toString().toLowerCase();

    String badgeText;
    Color badgeColor;
    String subtitle;

    if (hasReplies) {
      if (parsedAction == 'confine') {
        badgeText = 'SMS: CONFINE';
        badgeColor = const Color(0xFF1D4ED8);
      } else if (parsedAction == 'take_back') {
        badgeText = 'SMS: TAKE BACK';
        badgeColor = const Color(0xFFEA580C);
      } else {
        final preview = latestMsg.length > 20 ? '${latestMsg.substring(0, 20)}…' : latestMsg;
        badgeText = 'SMS: "$preview"';
        badgeColor = const Color(0xFF0F5132);
      }
      subtitle = '${replies.length} ${replies.length == 1 ? 'reply' : 'replies'} • Tap to view';
    } else if (isAntiMortemFailed || isPostMortemFailed) {
      badgeText = 'Walk-In • Awaiting SMS';
      badgeColor = const Color(0xFFD97706);
      subtitle = 'Tap to view / log reply';
    } else {
      badgeText = 'Walk-in Customer';
      badgeColor = Colors.grey;
      subtitle = 'Tap for SMS replies';
    }

    return InkWell(
      onTap: () => _showWalkInSmsRepliesDialog(req),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBadge(badgeText, badgeColor, light: true),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: hasReplies ? FontWeight.w600 : FontWeight.w400,
                color: hasReplies ? const Color(0xFF0F5132) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWalkInSmsRepliesDialog(Map<String, dynamic> req) {
    final reqId = req['id'];
    final reqIdStr = reqId?.toString() ?? '';
    final refNo = _refNo(req);
    final customerName = (req['customer_name'] ?? 'Walk-In Customer').toString();
    final contactNo = (req['contact_number'] ?? '').toString().trim();
    final status = (req['status'] ?? '').toString().toLowerCase();
    final manualReplyCtrl = TextEditingController();
    bool isSavingManual = false;
    List<Map<String, dynamic>> replies = List<Map<String, dynamic>>.from(
      _walkInSmsRepliesByReqId[reqIdStr] ?? const [],
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Container(
            width: 540,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.forum_outlined, color: Color(0xFF0F5132), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Walk-In Customer SMS Responses',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$customerName • $refNo${contactNo.isNotEmpty ? ' • $contactNo' : ''}',
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Color(0xFF64748B)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: replies.isEmpty
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mark_chat_unread_outlined, size: 28, color: Color(0xFF94A3B8)),
                              SizedBox(height: 8),
                              Text(
                                'No SMS reply received yet from this walk-in customer.',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Replies sent to your TextBee gateway SIM appear here automatically, or you can log a phone/SMS reply below.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: replies.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, idx) {
                            final item = replies[idx];
                            final msg = (item['message'] ?? '').toString();
                            final action = (item['parsed_action'] ?? 'reply').toString().toLowerCase();
                            final source = (item['source'] ?? 'textbee_webhook').toString();
                            final rawTime = item['received_at']?.toString();
                            String timeLabel = 'Just now';
                            if (rawTime != null && rawTime.isNotEmpty) {
                              final parsedDt = DateTime.tryParse(rawTime)?.toLocal();
                              if (parsedDt != null) {
                                timeLabel = DateFormat('MMM d, yyyy • h:mm a').format(parsedDt);
                              }
                            }
                            final actionBadgeColor = action == 'confine'
                                ? const Color(0xFF1D4ED8)
                                : (action == 'take_back' ? const Color(0xFFEA580C) : const Color(0xFF0F5132));
                            final actionLabel = action == 'confine'
                                ? 'CONFINE'
                                : (action == 'take_back' ? 'TAKE BACK' : 'SMS REPLY');

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      _buildBadge(actionLabel, actionBadgeColor, light: true),
                                      const SizedBox(width: 8),
                                      Text(
                                        source == 'manual_log' ? 'Logged by Staff' : 'Received via SMS',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                      const Spacer(),
                                      Text(
                                        timeLabel,
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    msg,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      color: Color(0xFF0F172A),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Log Phone / SMS Reply Manually (Fallback)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: manualReplyCtrl,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. CONFINE — customer agreed to 2-day observation',
                          hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: isSavingManual
                          ? null
                          : () async {
                              final txt = manualReplyCtrl.text.trim();
                              if (txt.isEmpty) return;
                              setModalState(() => isSavingManual = true);
                              final upper = txt.toUpperCase();
                              final parsed = RegExp(r'\b(TAKE\s*BACK|TAKEBACK|PICK\s*UP|PICKUP|RETRIEVE)\b').hasMatch(upper)
                                  ? 'take_back'
                                  : (RegExp(r'\b(CONFINE|OBSERVE|KEEP|YES|AGREE|OK)\b').hasMatch(upper)
                                      ? 'confine'
                                      : 'reply');
                              try {
                                final inserted = await supabase
                                    .from('walkin_sms_replies')
                                    .insert({
                                      'request_id': reqId,
                                      'sender_phone': contactNo.isNotEmpty ? contactNo : 'walk-in',
                                      'message': txt,
                                      'parsed_action': parsed,
                                      'source': 'manual_log',
                                    })
                                    .select()
                                    .single();
                                if ((parsed == 'confine' || parsed == 'take_back') &&
                                    (status == 'anti_mortem_failed' || status == 'delay_error')) {
                                  await supabase.from('requests').update({
                                    'anti_mortem_response': parsed,
                                    'anti_mortem_response_at': DateTime.now().toUtc().toIso8601String(),
                                  }).eq('id', reqId);
                                }
                                manualReplyCtrl.clear();
                                setModalState(() {
                                  replies.insert(0, Map<String, dynamic>.from(inserted));
                                  isSavingManual = false;
                                });
                                _loadRequests(silent: true);
                              } catch (e) {
                                setModalState(() => isSavingManual = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Could not save reply (run walkin_sms_replies SQL migration first): $e'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F5132),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: isSavingManual
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save Reply', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (contactNo.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          final isAmFail = status == 'anti_mortem_failed' || status == 'pickup_scheduled';
                          final isPmFail = status == 'post_mortem_failed' || status == 'condemned';
                          WalkInSmsHelper.showSmsFeedbackDialog(
                            context: context,
                            contactNumber: contactNo,
                            stage: isAmFail
                                ? 'ante_mortem_failed'
                                : (isPmFail ? 'post_mortem_failed' : 'inspection'),
                            refNo: refNo,
                            customerName: customerName,
                            marking: (req['marking'] ?? '').toString(),
                            livestockType: (req['livestock_type'] ?? '').toString(),
                            animalCount: (req['animal_count'] as num?)?.toInt() ?? 1,
                            statusSummary: status.replaceAll('_', ' '),
                            findings: (req['condemnation_reason'] ?? req['veterinary_findings'] ?? '').toString(),
                            inspectorName: (req['inspector_name'] ?? '').toString(),
                            requestId: reqIdStr,
                          );
                        },
                        icon: const Icon(Icons.sms_outlined, size: 15),
                        label: const Text('Send Follow-Up SMS'),
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => manualReplyCtrl.dispose());
  }

  Widget _buildAntiMortemStatusBadge(Map<String, dynamic> req, String status, String? customerResponse) {
    if (status == 'taken_back') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFE6F9F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.3)),
        ),
        child: const Text('Taken Back (Released)', style: TextStyle(fontSize: 10, color: Color(0xFF2D6A4F), fontWeight: FontWeight.w600)),
      );
    }
    if (status == 'pickup_scheduled') {
      final pickupStr = req['pickup_time']?.toString();
      DateTime? dt;
      if (pickupStr != null) dt = DateTime.tryParse(pickupStr);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFEBF8FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBEE3F8)),
        ),
        child: Text(
          dt != null ? 'Pickup: ${DateFormat('MMM d, h:mm a').format(dt)}' : 'Pickup Scheduled',
          style: const TextStyle(fontSize: 10, color: Color(0xFF2B6CB0), fontWeight: FontWeight.w600),
        ),
      );
    }
    if (customerResponse == 'confine' || status == 'anti_mortem_failed' || status == 'confined') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCD34D)),
        ),
        child: const Text('Confined (Under Observation)', style: TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
      );
    }
    if (customerResponse == 'take_back') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: const Text('Take Back Requested', style: TextStyle(fontSize: 10, color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: const Text('Ante-Mortem Failed', style: TextStyle(fontSize: 10, color: Color(0xFFC53030), fontWeight: FontWeight.w600)),
    );
  }

  void _showClearConfinementDialog(Map<String, dynamic> req) {
    final ref = _refNo(req);
    final customer = req['customer_name'] ?? 'Customer';
    final livestock = req['livestock_type'] ?? 'Livestock';
    final count = req['animal_count'] ?? 1;
    final reasonCtrl = TextEditingController();
    final confStart = ConfinementScheduleHelper.resolveConfinementStart(req);
    final confEnd = ConfinementScheduleHelper.resolveConfinementEnd(req);
    final isEnded = ConfinementScheduleHelper.isConfinementEnded(req);
    final startLabel = ConfinementScheduleHelper.formatStartLabel(confStart);
    final endLabel = ConfinementScheduleHelper.formatEndLabel(confEnd);
    final remainingLabel = ConfinementScheduleHelper.formatRemainingLabel(confEnd);
    bool earlyOverride = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final canEvaluate = isEnded || earlyOverride;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.local_hospital_outlined, color: Color(0xFF185FA5), size: 24),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Evaluate Confined Livestock',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This livestock was placed in 2-day facility confinement after failing ante-mortem inspection. Once the confinement period ends, notify the customer whether slaughter will continue or if the livestock must be condemned:',
                      style: TextStyle(fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isEnded ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isEnded ? const Color(0xFF6EE7B7) : const Color(0xFFFCD34D),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order: $ref | $customer',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isEnded ? const Color(0xFF065F46) : const Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Livestock: $livestock ($count head)',
                            style: TextStyle(
                              fontSize: 12,
                              color: isEnded ? const Color(0xFF065F46) : const Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Confinement Started: $startLabel',
                            style: TextStyle(
                              fontSize: 12,
                              color: isEnded ? const Color(0xFF047857) : const Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '2-Day Confinement Ends: $endLabel',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isEnded ? const Color(0xFF065F46) : const Color(0xFFB45309),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                isEnded ? Icons.check_circle_outline : Icons.hourglass_top_rounded,
                                size: 14,
                                color: isEnded ? const Color(0xFF059669) : const Color(0xFFD97706),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  isEnded
                                      ? 'Confinement Ended — Ready to Notify Customer (Continue or Condemn)'
                                      : 'Under 2-Day Observation ($remainingLabel)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isEnded ? const Color(0xFF059669) : const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!isEnded) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: CheckboxListTile(
                          value: earlyOverride,
                          onChanged: (v) => setDialogState(() => earlyOverride = v ?? false),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: const Color(0xFF1E855A),
                          title: const Text(
                            'Early Veterinary Override',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                          ),
                          subtitle: Text(
                            'Unlock Continue / Condemn decision before $endLabel for urgent veterinary clearance or condemnation.',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'Inspector Remarks / Condemnation Reason',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF2D3748)),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: const [SentencesCapitalizationFormatter()],
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Enter clearance notes or reason if condemning livestock...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12.5),
                        filled: true,
                        fillColor: const Color(0xFFF7FAFC),
                        contentPadding: const EdgeInsets.all(10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.gpp_bad_outlined, size: 16),
                onPressed: !canEvaluate
                    ? null
                    : () async {
                        final reason = reasonCtrl.text.trim().isNotEmpty
                            ? reasonCtrl.text.trim()
                            : 'Condemned following ante-mortem confinement evaluation';
                        Navigator.pop(ctx);
                        await _condemnConfinedLivestock(req, reason);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC0392B),
                  foregroundColor: Colors.white,
                ),
                label: const Text('Condemn Livestock'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                onPressed: !canEvaluate
                    ? null
                    : () async {
                        final notes = reasonCtrl.text.trim();
                        Navigator.pop(ctx);
                        await _clearConfinementAndResumeSlaughter(req, notes: notes);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E855A),
                  foregroundColor: Colors.white,
                ),
                label: const Text('Cleared & Resume Slaughter'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _condemnConfinedLivestock(Map<String, dynamic> req, String reason) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final livestockType = req['livestock_type'] ?? 'Livestock';
      final animalCount = req['animal_count'] ?? 1;
      final defaultInspector = AppSettingsService.instance.configuredInspectors.isNotEmpty
          ? AppSettingsService.instance.configuredInspectors.first
          : 'Dr. Maria Clara Reyes';
      final inspectorName = (req['inspector_name']?.toString().trim().isNotEmpty == true)
          ? req['inspector_name'].toString().trim()
          : defaultInspector;

      await supabase.from('requests').update({
        'status': 'post_mortem_failed',
      }).eq('id', reqId);

      final existingInsp = await supabase
          .from('slaughter_inspection')
          .select('id')
          .eq('request_id', reqId)
          .maybeSingle();

      final inspData = {
        'request_id': reqId,
        'anti_mortem': 'Failed',
        'post_mortem': 'Failed',
        'process_stage': 'Condemned',
        'inspector_name': inspectorName,
        'condemnation_reason': reason,
        'process_notes': 'Condemned after facility confinement evaluation: $reason',
      };
      if (existingInsp != null) {
        await supabase.from('slaughter_inspection').update(inspData).eq('request_id', reqId);
      } else {
        await supabase.from('slaughter_inspection').insert(inspData);
      }

      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: '$livestockType — Condemned Following Confinement',
        message: 'Following veterinary confinement and re-evaluation, your $animalCount head(s) of $livestockType was deemed unfit for slaughter and must be condemned ($reason). Please review the official condemnation slip.',
        type: 'post_mortem_failed',
        data: {
          'request_id': reqId,
          'customer_name': req['customer_name'],
          'livestock_type': livestockType,
          'condemnation_reason': reason,
          'inspector_name': inspectorName,
          'animal_count': animalCount,
          'carcass_weight': req['carcass_weight']?.toString() ?? '',
          'process_notes': reason,
        },
      );

      // Auto-send detailed Post-Mortem / Condemnation SMS for walk-in customers (details only, no slip document)
      final walkInPhone = (req['contact_number'] ?? '').toString().trim();
      if (walkInPhone.isNotEmpty) {
        final refNoStr = _refNo(req);
        final smsBody = WalkInSmsHelper.buildDefaultMessage(
          stage: 'post_mortem_failed',
          refNo: refNoStr,
          customerName: (req['customer_name'] ?? 'Customer').toString(),
          marking: (req['marking'] ?? '').toString(),
          livestockType: livestockType.toString(),
          animalCount: (animalCount as num?)?.toInt() ?? 1,
          findings: reason,
          inspectorName: inspectorName,
        );
        WalkInSmsService.sendSms(
          phone: walkInPhone,
          message: smsBody,
          stage: 'post_mortem_failed',
          refNo: refNoStr,
          customerName: (req['customer_name'] ?? 'Customer').toString(),
          requestId: reqId?.toString(),
        );
      }

      await _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.gpp_bad_outlined, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Confined livestock marked as Condemned. Customer notified with Condemnation Slip.'),
            ]),
            backgroundColor: Color(0xFFC0392B),
          ),
        );
        showDialog(
          context: context,
          builder: (_) => _CondemnationSlipDialog(
            request: req,
            condemnationReason: reason,
            inspectorName: inspectorName,
            carcassWeight: req['carcass_weight']?.toString() ?? '',
            supabase: supabase,
            onDone: _loadRequests,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error condemning livestock: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _clearConfinementAndResumeSlaughter(Map<String, dynamic> req, {String notes = ''}) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final livestockType = req['livestock_type'] ?? 'Livestock';
      final animalCount = req['animal_count'] ?? 1;
      final refNo = _refNo(req);

      // 1. Update requests status to slaughter_started
      await supabase.from('requests').update({
        'status': 'slaughter_started',
      }).eq('id', reqId);

      // 2. Update slaughter_inspection
      final existingInsp = await supabase.from('slaughter_inspection').select('id').eq('request_id', reqId).maybeSingle();
      final defaultInspector = AppSettingsService.instance.configuredInspectors.isNotEmpty
          ? AppSettingsService.instance.configuredInspectors.first
          : 'Dr. Maria Clara Reyes';
      final nowUtcIso = DateTime.now().toUtc().toIso8601String();
      final resolvedNotesBase = notes.isNotEmpty
          ? 'Cleared after confinement and observation: $notes'
          : 'Cleared after confinement and observation. Resumed active slaughter at Stunning stage.';
      final resolvedNotes = '[AM_PASSED_AT:$nowUtcIso] $resolvedNotesBase';
      final inspData = <String, dynamic>{
        'request_id': reqId,
        'anti_mortem': 'Passed',
        'process_stage': 'Stunning',
        'ante_mortem_passed_at': nowUtcIso,
        'inspector_name': defaultInspector,
        'process_notes': resolvedNotes,
      };
      Future<void> saveClearedInsp(Map<String, dynamic> p) async {
        if (existingInsp != null) {
          await supabase.from('slaughter_inspection').update(p).eq('request_id', reqId);
        } else {
          await supabase.from('slaughter_inspection').insert(p);
        }
      }
      try {
        await saveClearedInsp(inspData);
      } catch (_) {
        inspData.remove('ante_mortem_passed_at');
        await saveClearedInsp(inspData);
      }

      // 3. Notify customer
      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: '$livestockType — Cleared & Ready for Slaughter',
        message: 'Your $animalCount head(s) of $livestockType ($refNo) has been cleared by the veterinarian and is now ready for slaughter. Slaughter operations have resumed at the Stunning stage.',
        type: 'slaughter_started',
        data: {
          'request_id': reqId,
          'reference_no': refNo,
          'livestock_type': livestockType,
          'process_stage': 'Stunning',
        },
      );

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Livestock cleared! Moved to active slaughter queue (Stunning). Customer notified.'),
            ]),
            backgroundColor: Color(0xFF1E855A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing confinement: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showConfirmTakenBackDialog(Map<String, dynamic> req) {
    final ref = _refNo(req);
    final customer = req['customer_name'] ?? 'Customer';
    final livestock = req['livestock_type'] ?? 'Livestock';
    final count = req['animal_count'] ?? 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.handshake_outlined, color: Color(0xFFC0392B), size: 24),
            SizedBox(width: 8),
            Text('Confirm Animal Handover', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Confirm that the customer or authorized representative has physically taken back $count head(s) of $livestock at the slaughterhouse corral.',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFEB2B2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order: $ref | $customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF991B1B))),
                    const SizedBox(height: 4),
                    Text('Livestock: $livestock ($count head)', style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B))),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.done_all, size: 16),
            onPressed: () async {
              Navigator.pop(ctx);
              await _confirmAnimalTakenBack(req);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC0392B),
              foregroundColor: Colors.white,
            ),
            label: const Text('Confirm Animal Handover Complete'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAnimalTakenBack(Map<String, dynamic> req) async {
    try {
      final reqId = req['id'];
      final userId = req['user_id'];
      final livestockType = req['livestock_type'] ?? 'Livestock';
      final refNo = _refNo(req);
      final formattedTime = DateFormat('h:mm a, MMMM d, yyyy').format(DateTime.now());

      await supabase.from('requests').update({
        'status': 'taken_back',
        'released_at': DateTime.now().toIso8601String(),
      }).eq('id', reqId);

      await NotificationService.sendNotificationSafely(
        supabase,
        userId: userId,
        title: '$livestockType — Handover Complete',
        message: 'Your $livestockType ($refNo) was officially released and handed over to you at the slaughterhouse corral at $formattedTime. Thank you!',
        type: 'taken_back',
        data: {
          'request_id': reqId,
          'reference_no': refNo,
          'livestock_type': livestockType,
          'verified_at': formattedTime,
        },
      );

      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.verified, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Livestock handover confirmed! Status set to Taken Back.'),
            ]),
            backgroundColor: Color(0xFFC0392B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error confirming handover: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildBadge(String text, Color color, {bool outline = false, bool light = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : (light ? color.withValues(alpha: 0.1) : color),
        border: outline ? Border.all(color: color) : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: outline ? color : (light ? color : Colors.white))),
    );
  }
}

class _UpdateProcessDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final SupabaseClient supabase;
  final VoidCallback onDone;

  const _UpdateProcessDialog({required this.request, required this.supabase, required this.onDone});

  @override
  State<_UpdateProcessDialog> createState() => _UpdateProcessDialogState();
}

class _UpdateProcessDialogState extends State<_UpdateProcessDialog> {
  bool _isLoading = false;
  late String _antiMortem;
  late String _processStage;
  late String _postMortem;
  final _carcassCtrl = TextEditingController();
  final _inspectorCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late List<String> _inspectors;
  String? _selectedInspector;

  bool _healthIssueDetected = false;
  final _condemnationCtrl = TextEditingController();
  String? _condemnationType = 'Partial Condemnation';
  TextEditingController? _condemnedPartCtrlField;
  TextEditingController? _condemnedWeightCtrlField;
  TextEditingController? _condemnationReasonCtrlField;
  bool? _condemnationSlipGeneratedField = false;
  int _condemnedCount = 1;
  int _confinementDays = 2;

  String get _resolvedCondemnationType =>
      (_condemnationType == 'Whole Condemnation')
          ? 'Whole Condemnation'
          : 'Partial Condemnation';
  TextEditingController get _condemnedPartCtrl =>
      _condemnedPartCtrlField ??= TextEditingController();
  TextEditingController get _condemnedWeightCtrl =>
      _condemnedWeightCtrlField ??= TextEditingController(text: '0');
  TextEditingController get _condemnationReasonCtrl =>
      _condemnationReasonCtrlField ??= TextEditingController();
  bool get _condemnationSlipGenerated => _condemnationSlipGeneratedField == true;
  set _condemnationSlipGenerated(bool v) => _condemnationSlipGeneratedField = v;

  String get _condemnationSlipNo {
    final idNum = (widget.request['id'] ?? 0).toString().padLeft(4, '0');
    return 'CS-${DateTime.now().year}-$idNum';
  }

  String _buildStructuredCondemnationSummary() {
    final typeLabel = _resolvedCondemnationType;
    final isPartial = typeLabel == 'Partial Condemnation';
    final part = isPartial
        ? _condemnedPartCtrl.text.trim()
        : (_condemnedPartCtrl.text.trim().isNotEmpty
            ? _condemnedPartCtrl.text.trim()
            : 'Whole Carcass');
    final wtStr = _condemnedWeightCtrl.text.trim().isEmpty
        ? '0'
        : _condemnedWeightCtrl.text.trim();
    final reason = _condemnationReasonCtrl.text.trim();
    return '[$typeLabel | Slip: $_condemnationSlipNo | Part: $part | Weight: $wtStr kg] $reason';
  }

  Future<void> _handleGenerateCondemnationSlip() async {
    final isPartial = _resolvedCondemnationType == 'Partial Condemnation';
    final part = _condemnedPartCtrl.text.trim();
    final reason = _condemnationReasonCtrl.text.trim();

    if (isPartial && part.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the condemned part (e.g., Liver, Lungs).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the condemnation reason (e.g., Pneumonia, Bruising).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final summary = _buildStructuredCondemnationSummary();
    setState(() {
      _condemnationCtrl.text = summary;
      _condemnationSlipGenerated = true;
      if (!isPartial) {
        _healthIssueDetected = true;
        _postMortem = 'Failed';
      } else {
        _healthIssueDetected = false;
      }
    });

    final inspector = _selectedInspector ?? _inspectorCtrl.text.trim();
    final weightDisplay = _condemnedWeightCtrl.text.trim().isNotEmpty &&
            _condemnedWeightCtrl.text.trim() != '0'
        ? _condemnedWeightCtrl.text.trim()
        : (_carcassCtrl.text.trim().isNotEmpty ? _carcassCtrl.text.trim() : '0');

    await showDialog(
      context: context,
      builder: (_) => _CondemnationSlipDialog(
        request: widget.request,
        condemnationReason: summary,
        inspectorName: inspector.isNotEmpty ? inspector : 'Meat Inspector',
        carcassWeight: weightDisplay,
        supabase: widget.supabase,
        isPartialCondemnation: isPartial,
        slipNumber: _condemnationSlipNo,
        onDone: () {
          if (!isPartial) {
            widget.onDone();
          }
        },
      ),
    );
  }

  int get _totalHeads => int.tryParse(widget.request['animal_count']?.toString() ?? '1') ?? 1;
  bool get _isPartialPartCondemnation =>
      _postMortem == 'Failed' && _resolvedCondemnationType == 'Partial Condemnation';
  bool get _isWholeCondemnation =>
      _postMortem == 'Failed' && _resolvedCondemnationType == 'Whole Condemnation';
  bool get _hasHealthFailure => _antiMortem == 'Failed' || _isWholeCondemnation;
  int get _effectivePassedCount {
    if (!_hasHealthFailure) return _totalHeads;
    return (_totalHeads - _condemnedCount).clamp(0, _totalHeads);
  }
  bool get _isPartialBatch => _totalHeads >= 2 && _hasHealthFailure && _condemnedCount > 0 && _effectivePassedCount > 0;

  // (Technical Error/Delay UI removed from Update Slaughter Process dialog)
  final _delayReasonCtrl = TextEditingController();
  bool _isMissedSchedule = false;
  int _customerPriorMissedCount = 0;
  String _emergencyCause = 'Heat Stroke';
  final List<String> _emergencyCauses = const [
    'Heat Stroke',
    'Transit Stress',
    'Accidental / Transit Injury',
    'Other Non-Infectious Cause',
  ];

  (double min, double max) _getAcceptableWeightRange(String? type, int count) {
    final t = (type ?? '').toLowerCase();
    final heads = count > 0 ? count : 1;
    if (t.contains('cattle') || t.contains('cow') || t.contains('carabao')) {
      return (100.0 * heads, 500.0 * heads);
    } else if (t.contains('goat') || t.contains('sheep')) {
      return (10.0 * heads, 40.0 * heads);
    } else if (t.contains('poultry') || t.contains('chicken')) {
      return (0.8 * heads, 5.0 * heads);
    }
    // Default to Hog / Swine / Pig
    return (40.0 * heads, 160.0 * heads);
  }

  bool _isWeightInRange(double weight, String? type, int count) {
    final range = _getAcceptableWeightRange(type, count);
    return weight >= range.$1 && weight <= range.$2;
  }

  void _checkAutoDetermination() {
    final count = _effectivePassedCount > 0 ? _effectivePassedCount : _totalHeads;
    final type = widget.request['livestock_type']?.toString();
    final weight = double.tryParse(_carcassCtrl.text.trim());

    // 0. While Ante-Mortem is Pending, lock process stage at Ante-Mortem
    if (_antiMortem == 'Pending') {
      _processStage = 'Ante-Mortem';
      return;
    }

    // 1. If Ante-Mortem is Separate Facility, bypass standard floor stages to 'Separate Facility (Weighing)'
    if (_antiMortem == 'Separate Facility') {
      if (_processStage != 'Complete') {
        _processStage = 'Separate Facility (Weighing)';
      }
    } else if (_antiMortem == 'Passed' || _isPartialBatch) {
      if (_processStage == 'Ante-Mortem' ||
          _processStage == 'Anti-Mortem' ||
          _processStage == 'Preparation') {
        _processStage = 'Stunning';
      }
    }

    // 2. Early override / completion: auto-mark Complete if weight is entered & within acceptable range AND (Post-Mortem passes, Partial Part Condemnation, or partial batch has healthy heads)
    if (weight != null &&
        _isWeightInRange(weight, type, count) &&
        (_postMortem == 'Passed' || _isPartialPartCondemnation || _isPartialBatch)) {
      _processStage = 'Complete';
    } else if (_processStage == 'Complete' && (weight == null || !_isWeightInRange(weight, type, count))) {
      // Revert if weight is removed or not acceptable
      _processStage = _antiMortem == 'Separate Facility' ? 'Separate Facility (Weighing)' : 'Weighing';
    }
  }

  @override
  void initState() {
    super.initState();
    final req = widget.request;
    final validAntiMortem = ['Pending', 'Passed', 'Failed', 'Separate Facility'];
    final rawAntiMortem = req['anti_mortem']?.toString() ?? 'Pending';
    _antiMortem = validAntiMortem.contains(rawAntiMortem) ? rawAntiMortem : 'Pending';
    final validStages = [
      'Separate Facility (Weighing)',
      'Ante-Mortem',
      'Preparation',
      'Stunning',
      'Bleeding',
      'Scalding/Dehairing',
      'Evisceration',
      'Post-Mortem Inspection',
      'Weighing',
      'Complete',
      'Technical Error/Delay',
    ];
    final rawReqStage = (req['process_stage'] ?? 'Ante-Mortem').toString();
    final normalizedReqStage = rawReqStage == 'Scalding/Plucking' ? 'Scalding/Dehairing' : rawReqStage;
    if (_antiMortem == 'Pending') {
      _processStage = 'Ante-Mortem';
    } else {
      _processStage = validStages.contains(normalizedReqStage) ? normalizedReqStage : 'Stunning';
    }
    final rawPostMortem = (req['post_mortem'] ?? 'Pending').toString();
    if (rawPostMortem.toLowerCase() == 'partially condemned') {
      _postMortem = 'Failed';
      _condemnationType = 'Partial Condemnation';
    } else if (['Pending', 'Passed', 'Failed'].contains(rawPostMortem)) {
      _postMortem = rawPostMortem;
    } else {
      _postMortem = 'Pending';
    }
    if (req['carcass_weight'] != null) _carcassCtrl.text = req['carcass_weight'].toString();

    final rawNotes = (req['process_notes'] ?? '').toString();
    final causeMatch = RegExp(r'Cause:\s*([^\]]+)').firstMatch(rawNotes);
    if (causeMatch != null) {
      final parsedCause = causeMatch.group(1)?.trim() ?? '';
      if (_emergencyCauses.contains(parsedCause)) {
        _emergencyCause = parsedCause;
      }
    }

    // Built-in inspector name based on staff accounts & roles
    _inspectors = AppSettingsService.instance.configuredInspectors;
    final existingInspector = req['inspector_name']?.toString().trim();
    if (existingInspector != null && existingInspector.isNotEmpty && _inspectors.contains(existingInspector)) {
      _selectedInspector = existingInspector;
    } else if (_inspectors.isNotEmpty) {
      _selectedInspector = _inspectors.first;
    } else {
      _selectedInspector = existingInspector ?? 'Dr. Maria Clara Reyes';
    }
    _inspectorCtrl.text = _selectedInspector ?? '';

    if (req['process_notes'] != null) {
      _notesCtrl.text = req['process_notes']
          .toString()
          .replaceAll(RegExp(r'\[AM_PASSED_AT:[^\]]+\]\s*\|?\s*'), '')
          .replaceAll(RegExp(r'\[COMPLETED_AT:[^\]]+\]\s*\|?\s*'), '')
          .trim();
    }
    if (req['condemnation_reason'] != null && req['condemnation_reason'].toString().trim().isNotEmpty) {
      final rawReason = req['condemnation_reason'].toString().trim();
      _condemnationCtrl.text = rawReason;
      _condemnationSlipGenerated = true;
      if (rawReason.contains('[Partial Condemnation')) {
        _condemnationType = 'Partial Condemnation';
        _healthIssueDetected = false;
        final partM = RegExp(r'Part:\s*([^|\]]+)').firstMatch(rawReason);
        final wtM = RegExp(r'Weight:\s*([0-9.]+)').firstMatch(rawReason);
        final afterBracket = rawReason.contains(']') ? rawReason.split(']').last.trim() : rawReason;
        if (partM != null) _condemnedPartCtrl.text = partM.group(1)?.trim() ?? '';
        if (wtM != null) _condemnedWeightCtrl.text = wtM.group(1)?.trim() ?? '0';
        _condemnationReasonCtrl.text = afterBracket;
      } else {
        _condemnationType = 'Whole Condemnation';
        _healthIssueDetected = true;
        final afterBracket = rawReason.contains(']') ? rawReason.split(']').last.trim() : rawReason;
        _condemnationReasonCtrl.text = afterBracket;
      }
    }
    final existingCondemned = int.tryParse(req['condemned_count']?.toString() ?? '');
    if (existingCondemned != null && existingCondemned >= 1 && existingCondemned <= _totalHeads) {
      _condemnedCount = existingCondemned;
    } else {
      _condemnedCount = _totalHeads >= 2 ? 1 : _totalHeads;
    }
    if (req['delay_reason'] != null) {
      _delayReasonCtrl.text = req['delay_reason'].toString();
    } else {
      final notes = (req['process_notes'] ?? '').toString();
      final match = RegExp(r'Technical delay\s*(?:\([^)]*\))?:\s*(.*)').firstMatch(notes);
      if (match != null) {
        _delayReasonCtrl.text = match.group(1) ?? '';
      }
    }
    // Technical Error/Delay dialog toggle removed

    if (_SlaughterInspectionPageState.isPastMissedScheduleCutoff(req)) {
      _isMissedSchedule = true;
    }
    if (req['penalty_fee'] != null && (double.tryParse(req['penalty_fee'].toString()) ?? 0.0) > 0) {
      _isMissedSchedule = true;
    }
    if (req['is_warning_only'] == true || (req['process_notes'] ?? '').toString().contains('1ST OFFENSE')) {
      _isMissedSchedule = true;
    }

    _loadCustomerMissedScheduleHistory();

    _carcassCtrl.addListener(() {
      if (mounted) {
        setState(() {
          _checkAutoDetermination();
        });
      }
    });
  }

  Future<void> _loadCustomerMissedScheduleHistory() async {
    if (!mounted) return;
    try {
      final customerKey = (widget.request['user_id'] ??
              widget.request['contact_number'] ??
              widget.request['customer_name'] ??
              '')
          .toString()
          .trim();
      final currentReqId = widget.request['id']?.toString() ?? '';

      final row = await widget.supabase
          .from('system_settings')
          .select('value')
          .eq('key', 'customer_missed_schedule_history')
          .maybeSingle();

      if (row != null && row['value'] is Map) {
        final histMap = Map<String, dynamic>.from(row['value']);
        if (customerKey.isNotEmpty && histMap.containsKey(customerKey)) {
          final cData = histMap[customerKey];
          if (cData is Map) {
            final records = (cData['records'] as List?) ?? [];
            final priorRecords = records
                .where((rec) => rec['request_id']?.toString() != currentReqId)
                .toList();
            if (mounted) {
              setState(() {
                _customerPriorMissedCount = priorRecords.length;
              });
            }
          } else if (cData is num) {
            if (mounted) {
              setState(() {
                _customerPriorMissedCount = cData.toInt();
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading customer missed schedule history: $e');
    }
  }

  Future<void> _updateProcess({bool notifyDelay = false}) async {
    final weight = double.tryParse(_carcassCtrl.text.trim());

    if (_processStage == 'Complete' && !notifyDelay) {
      if (weight == null || weight <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Warning: Carcass weight is required before marking as Complete.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // Validate condemnation details whenever Post-Mortem Failed is selected
    if (_postMortem == 'Failed' && !notifyDelay) {
      final part = _condemnedPartCtrl.text.trim();
      final reason = _condemnationReasonCtrl.text.trim();
      if (_isPartialPartCondemnation && part.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter the condemned part (e.g., Liver, Lungs) for Partial Condemnation.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter the condemnation reason before saving Post-Mortem Failed.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      _condemnationCtrl.text = _buildStructuredCondemnationSummary();
      _condemnationSlipGenerated = true;
      _healthIssueDetected = _isWholeCondemnation;
    }

    setState(() => _isLoading = true);
    try {
      final reqId = widget.request['id'];
      final userId = widget.request['user_id'];
      // refNo could be used in future for logging
      // final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // Validate inputs if needed...
      
      final customerKey = (widget.request['user_id'] ??
              widget.request['contact_number'] ??
              widget.request['customer_name'] ??
              '')
          .toString()
          .trim();
      final isRepeatOffense = _customerPriorMissedCount >= 1;
      final offenseLevel = isRepeatOffense ? (_customerPriorMissedCount + 1) : 1;
      final double computedPenaltyFee = _isMissedSchedule ? (isRepeatOffense ? 500.0 : 0.0) : 0.0;

      final bool isPartialBatch = _isPartialBatch;
      final int passedCount = _effectivePassedCount;
      final int condemnedCount = _hasHealthFailure ? _condemnedCount.clamp(1, _totalHeads) : 0;

      String newStatus = widget.request['status'];
      String? notifTitle;
      String? notifMessage;
      String? notifType;
      Map<String, dynamic>? notifData;

      // Partial batch: 2+ heads where some passed and some failed at Ante-Mortem or Post-Mortem
      if (isPartialBatch) {
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
        final reason = _condemnationCtrl.text.trim().isNotEmpty
            ? _condemnationCtrl.text.trim()
            : (_notesCtrl.text.trim().isNotEmpty
                ? _notesCtrl.text.trim()
                : 'Health issue detected on $condemnedCount of $_totalHeads head(s)');

        if (_processStage == 'Complete') {
          newStatus = 'releasable';
          final weightStr = _carcassCtrl.text.trim();
          final weightInfo = weightStr.isNotEmpty ? ' with a carcass weight of $weightStr kg' : '';
          final isMarket = (widget.request['request_type'] ?? '').toString().toLowerCase() == 'market';
          notifTitle = isMarket
              ? 'Partial Batch Ready for Delivery ($passedCount of $_totalHeads Passed)'
              : 'Partial Batch Ready for Collection ($passedCount of $_totalHeads Passed)';
          notifMessage = isMarket
              ? '$passedCount head(s) of $livestockType ($refNo) passed inspection$weightInfo and are ready for delivery ($condemnedCount head(s) condemned: $reason). Please settle payment via online payment or cashier.'
              : '$passedCount head(s) of $livestockType ($refNo) passed inspection$weightInfo and are ready for collection ($condemnedCount head(s) condemned: $reason). Please settle payment at the cashier counter before pickup.';
          notifType = 'slaughter_completed';
          notifData = {
            'request_id': reqId,
            'livestock_type': livestockType,
            'animal_count': passedCount,
            'total_animal_count': _totalHeads,
            'passed_count': passedCount,
            'condemned_count': condemnedCount,
            'carcass_weight': double.tryParse(_carcassCtrl.text),
            'inspector_name': _inspectorCtrl.text,
            'post_mortem': _postMortem,
            'process_stage': _processStage,
            'penalty_fee': computedPenaltyFee,
            'is_warning_only': !isRepeatOffense,
            'offense_level': offenseLevel,
          };
        } else {
          newStatus = 'slaughter_started';
        }
      } else if (_antiMortem == 'Failed') {
        newStatus = 'anti_mortem_failed';
        _processStage = 'Ante-Mortem';
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final vetFindings = _notesCtrl.text.isNotEmpty ? _notesCtrl.text : 'Health issue detected during ante-mortem inspection';
        final confEnd = ConfinementScheduleHelper.computeConfinementEnd(DateTime.now());
        final confEndLabel = ConfinementScheduleHelper.formatEndLabel(confEnd);
        notifTitle = '$livestockType — Placed in 2-Day Confinement (Ante-Mortem Failed)';
        notifMessage = 'Ante-mortem inspection failed ($vetFindings). Your livestock has been placed in 2-day facility confinement ending on $confEndLabel. Once the 2-day confinement ends, the inspector will re-evaluate and notify you whether slaughter will continue or if it must be condemned.';
        notifType = 'anti_mortem_failed';
        notifData = {
          'request_id': reqId,
          'livestock_type': livestockType,
          'veterinary_findings': vetFindings,
          'inspector_name': _inspectorCtrl.text,
          'animal_count': widget.request['animal_count'],
          'confinement_ends_at': confEnd.toUtc().toIso8601String(),
          'confinement_ends_label': confEndLabel,
        };
      } else if (notifyDelay) {
        newStatus = 'delay_error';
        _processStage = 'Technical Error/Delay';
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final delayReason = _delayReasonCtrl.text.trim();
        final reasonSuffix = delayReason.isNotEmpty ? ': $delayReason' : '';
        notifTitle = '$livestockType Operation Delayed (Facility Delay)';
        notifMessage = '$livestockType slaughter was delayed due to an internal slaughterhouse technical issue$reasonSuffix. No penalty fee will be charged to you (₱0.00 penalty). You may choose to keep your livestock in the facility for resumed processing or arrange retrieval at no charge.';
        notifType = 'operation_failed';
        notifData = {
          'request_id': reqId,
          'livestock_type': livestockType,
          'reason': delayReason,
          'penalty_fee': 0.0,
          'is_delayed': true,
          'actual_date': DateTime.now().toLocal().toIso8601String().split('T')[0],
        };
      } else if (!isPartialBatch && _isWholeCondemnation) {
        newStatus = 'post_mortem_failed';
        _processStage = 'Condemned';
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final reason = _condemnationCtrl.text.trim().isNotEmpty
            ? _condemnationCtrl.text.trim()
            : 'Condemned after slaughter';
        notifTitle = '$livestockType — Post-Mortem Failed (Whole Condemnation)';
        notifMessage = 'Health issues were found during post-mortem inspection after slaughter. Please review the condemnation slip.';
        notifType = 'post_mortem_failed';
        notifData = {
          'request_id': reqId,
          'customer_name': widget.request['customer_name'],
          'livestock_type': livestockType,
          'condemnation_reason': reason,
          'inspector_name': _inspectorCtrl.text,
          'animal_count': widget.request['animal_count'],
          'carcass_weight': _carcassCtrl.text,
          'process_notes': _notesCtrl.text,
        };
      } else if (!isPartialBatch && _isPartialPartCondemnation) {
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final animalCount = widget.request['animal_count'] ?? 1;
        final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
        final partName = _condemnedPartCtrl.text.trim();
        final partWt = _condemnedWeightCtrl.text.trim();
        final reasonSummary = _condemnationCtrl.text.trim();
        final weightStr = _carcassCtrl.text.trim();
        final weightInfo = weightStr.isNotEmpty ? ' ($weightStr kg usable carcass)' : '';

        if (_processStage == 'Complete') {
          newStatus = 'releasable';
          final isMarket = (widget.request['request_type'] ?? '').toString().toLowerCase() == 'market';
          notifTitle = isMarket
              ? 'Partially Condemned — Healthy Carcass Ready for Delivery'
              : 'Partially Condemned — Healthy Carcass Ready for Collection';
          notifMessage = isMarket
              ? 'Partial condemnation recorded for $livestockType ($refNo): $partName (${partWt}kg) condemned under Slip $_condemnationSlipNo. The remaining healthy carcass$weightInfo passed inspection and is ready for delivery — please settle payment via online payment or cashier.'
              : 'Partial condemnation recorded for $livestockType ($refNo): $partName (${partWt}kg) condemned under Slip $_condemnationSlipNo. The remaining healthy carcass$weightInfo passed inspection and is ready for collection — please settle payment at the cashier counter before pickup.';
          notifType = 'slaughter_completed';
          notifData = {
            'request_id': reqId,
            'livestock_type': livestockType,
            'animal_count': animalCount,
            'carcass_weight': double.tryParse(_carcassCtrl.text),
            'inspector_name': _inspectorCtrl.text,
            'post_mortem': 'Partially Condemned',
            'process_stage': _processStage,
            'condemnation_reason': reasonSummary,
            'condemned_part': partName,
            'condemned_weight': partWt,
            'slip_number': _condemnationSlipNo,
            'is_partial_condemnation': true,
            'penalty_fee': computedPenaltyFee,
            'is_warning_only': !isRepeatOffense,
            'offense_level': offenseLevel,
          };
        } else {
          newStatus = 'slaughter_started';
        }
      } else if (!isPartialBatch && _processStage == 'Complete' && _postMortem != 'Failed') {
        newStatus = 'releasable';
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final animalCount = widget.request['animal_count'] ?? 1;
        final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
        final weight = _carcassCtrl.text.trim();
        final weightInfo = weight.isNotEmpty ? ' with a carcass weight of $weight kg' : '';

        final isMarket = (widget.request['request_type'] ?? '').toString().toLowerCase() == 'market';
        if (isMarket) {
          notifTitle = 'Meat Ready for Delivery — Payment Required';
          notifMessage = 'Your $animalCount head(s) of $livestockType ($refNo) has been successfully slaughtered and passed post-mortem inspection$weightInfo. Market delivery is scheduled — please settle payment via GCash or cashier to clear your carcass for delivery dispatch.';
        } else {
          notifTitle = 'Meat Ready for Collection — Payment Required';
          notifMessage = 'Your $animalCount head(s) of $livestockType ($refNo) has been successfully slaughtered and passed post-mortem inspection$weightInfo. Under Cash-on-Pickup, please settle payment at the cashier counter upon arrival before carcass release. Reminder: Claim before 5:00 PM to avoid cold storage preservation fees.';
        }
        notifType = 'slaughter_completed';
        notifData = {
          'request_id': reqId,
          'livestock_type': livestockType,
          'animal_count': animalCount,
          'carcass_weight': double.tryParse(_carcassCtrl.text),
          'inspector_name': _inspectorCtrl.text,
          'post_mortem': _postMortem,
          'process_stage': _processStage,
          'penalty_fee': computedPenaltyFee,
          'is_warning_only': !isRepeatOffense,
          'offense_level': offenseLevel,
        };
      } else if (_antiMortem == 'Separate Facility') {
        newStatus = 'slaughter_started';
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final animalCount = widget.request['animal_count'] ?? 1;
        final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
        notifTitle = 'Separate Facility — Emergency Slaughter';
        notifMessage =
            'Your $animalCount head(s) of $livestockType ($refNo) arrived deceased due to $_emergencyCause (non-infectious) and is being processed immediately in the Separate Facility, bypassing the standard slaughterhouse queue.';
        notifType = 'separate_facility_slaughter';
        notifData = {
          'request_id': reqId,
          'livestock_type': livestockType,
          'animal_count': animalCount,
          'emergency_cause': _emergencyCause,
          'facility': 'Separate Facility',
        };
      } else if (_antiMortem == 'Passed' && _processStage != 'Complete') {
        final wasNotStarted = (widget.request['status'] ?? '').toString() == 'doc_verified' ||
            (widget.request['anti_mortem'] ?? 'Pending').toString() == 'Pending';
        newStatus = 'slaughter_started';
        if (wasNotStarted) {
          final livestockType = widget.request['livestock_type'] ?? 'Livestock';
          final animalCount = widget.request['animal_count'] ?? 1;
          final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
          notifTitle = 'Ante-Mortem Passed — Slaughter Started';
          notifMessage =
              'Your $animalCount head(s) of $livestockType ($refNo) passed ante-mortem veterinary inspection and is now proceeding through slaughter operations ($_processStage).';
          notifType = 'slaughter_started';
          notifData = {
            'request_id': reqId,
            'reference_no': refNo,
            'livestock_type': livestockType,
            'process_stage': _processStage,
          };
        }
      } else if (_antiMortem == 'Pending') {
        _processStage = 'Ante-Mortem';
      }

      final bool isImmediateSlaughterWalkIn = _antiMortem == 'Separate Facility' ||
          (widget.request['anti_mortem']?.toString() == 'Separate Facility') ||
          (widget.request['process_notes'] ?? '').toString().contains('SEPARATE FACILITY');
      final bool isPartialAnteConfinement =
          isPartialBatch && _antiMortem == 'Failed' && _postMortem != 'Failed' && !_healthIssueDetected;

      final reqUpdatePayload = <String, dynamic>{
        'status': newStatus,
        if (_antiMortem == 'Failed' && !isPartialBatch) ...{
          'anti_mortem_response': 'confine',
          'anti_mortem_response_at': DateTime.now().toIso8601String(),
        } else if (notifyDelay) ...{
          'anti_mortem_response': null,
          'anti_mortem_response_at': null,
        },
        if (isPartialAnteConfinement) ...{
          'animal_count': passedCount,
          'passed_count': passedCount,
          'condemned_count': 0,
        } else if (isPartialBatch) ...{
          'passed_count': passedCount,
          'condemned_count': condemnedCount,
        },
      };
      try {
        await widget.supabase.from('requests').update(reqUpdatePayload).eq('id', reqId);
      } catch (_) {
        reqUpdatePayload.remove('passed_count');
        reqUpdatePayload.remove('condemned_count');
        await widget.supabase.from('requests').update(reqUpdatePayload).eq('id', reqId);
      }

      final nowStr = DateTime.now().toLocal().toIso8601String().split('T')[0];

      // Persist Missed Schedule / Wasted Slot penalty or clear facility delay penalty in system_settings
      try {
        final settingsRow = await widget.supabase
            .from('system_settings')
            .select('value')
            .eq('key', 'pickup_penalty_tracking')
            .maybeSingle();
        Map<String, dynamic> trackMap = {};
        if (settingsRow != null && settingsRow['value'] is Map) {
          trackMap = Map<String, dynamic>.from(settingsRow['value']);
        }
        if (_isMissedSchedule) {
          final reqTrack = Map<String, dynamic>.from(trackMap[reqId.toString()] ?? {});
          reqTrack['penalty_fee'] = computedPenaltyFee;
          reqTrack['penalty_reason'] = isRepeatOffense
              ? 'Repeat Missed Schedule (#$offenseLevel) / Wasted Slot Penalty'
              : '1st Offense Missed Schedule (Warning Notice)';
          reqTrack['is_warning_only'] = !isRepeatOffense;
          reqTrack['offense_level'] = offenseLevel;
          reqTrack['actual_date'] = nowStr;
          trackMap[reqId.toString()] = reqTrack;
          await widget.supabase.from('system_settings').upsert({
            'key': 'pickup_penalty_tracking',
            'value': trackMap,
          });

          // Also record customer offense in customer_missed_schedule_history
          try {
            final histRow = await widget.supabase
                .from('system_settings')
                .select('value')
                .eq('key', 'customer_missed_schedule_history')
                .maybeSingle();
            Map<String, dynamic> allHist = {};
            if (histRow != null && histRow['value'] is Map) {
              allHist = Map<String, dynamic>.from(histRow['value']);
            }
            final cEntry = Map<String, dynamic>.from((allHist[customerKey] as Map?) ?? {});
            final recordsList = List<Map<String, dynamic>>.from((cEntry['records'] as List?) ?? []);
            recordsList.removeWhere((r) => r['request_id']?.toString() == reqId.toString());
            recordsList.add({
              'request_id': reqId,
              'reference_no': 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}',
              'scheduled_date': widget.request['preferred_date'],
              'actual_date': nowStr,
              'offense_level': offenseLevel,
              'action': isRepeatOffense ? 'penalty_charged' : 'warning_issued',
              'penalty_fee': computedPenaltyFee,
              'recorded_at': DateTime.now().toIso8601String(),
            });
            cEntry['count'] = recordsList.length;
            cEntry['records'] = recordsList;
            if (customerKey.isNotEmpty) {
              allHist[customerKey] = cEntry;
              await widget.supabase.from('system_settings').upsert({
                'key': 'customer_missed_schedule_history',
                'value': allHist,
              });
            }
          } catch (histErr) {
            debugPrint('Error updating customer_missed_schedule_history: $histErr');
          }
        } else if (notifyDelay && trackMap.containsKey(reqId.toString())) {
          trackMap.remove(reqId.toString());
          await widget.supabase.from('system_settings').upsert({
            'key': 'pickup_penalty_tracking',
            'value': trackMap,
          });
        }
      } catch (trackErr) {
        debugPrint('Error updating pickup_penalty_tracking: $trackErr');
      }

      final delayReason = _delayReasonCtrl.text.trim();
      final existingAmPassed = _SlaughterInspectionPageState._extractAmPassedAt(widget.request);
      final String? resolvedAmPassedIso = (_antiMortem == 'Passed' || isPartialAnteConfinement)
          ? (existingAmPassed?.toIso8601String() ?? DateTime.now().toUtc().toIso8601String())
          : null;

      String processNotes = _notesCtrl.text
          .trim()
          .replaceAll(RegExp(r'\[AM_PASSED_AT:[^\]]+\]\s*\|?\s*'), '')
          .replaceAll(RegExp(r'\[COMPLETED_AT:[^\]]+\]\s*\|?\s*'), '')
          .replaceAll(RegExp(r'\[PARTIAL BATCH:[^\]]+\]\s*\|?\s*', caseSensitive: false), '')
          .trim();
      if (resolvedAmPassedIso != null) {
        final amTag = '[AM_PASSED_AT:$resolvedAmPassedIso]';
        processNotes = processNotes.isEmpty ? amTag : '$amTag | $processNotes';
      }
      final bool isConcludingNow = _processStage == 'Complete' ||
          const {'releasable', 'mic_generated', 'post_mortem_failed', 'condemned'}.contains(newStatus);
      if (isConcludingNow) {
        final existingCompleted = RegExp(r'\[COMPLETED_AT:([^\]]+)\]')
            .firstMatch((widget.request['process_notes'] ?? '').toString())
            ?.group(1)
            ?.trim();
        final completedIso = existingCompleted ?? DateTime.now().toUtc().toIso8601String();
        final completedTag = '[COMPLETED_AT:$completedIso]';
        processNotes = processNotes.isEmpty ? completedTag : '$completedTag | $processNotes';
      }
      if (isPartialBatch) {
        final partialTag = '[PARTIAL BATCH: $passedCount Passed, $condemnedCount Condemned]';
        processNotes = processNotes.isEmpty ? partialTag : '$partialTag | $processNotes';
      }
      if (_isMissedSchedule && !processNotes.contains('MISSED SCHEDULE')) {
        final missedTag = isRepeatOffense
            ? '[REPEAT OFFENSE (#$offenseLevel): MISSED SCHEDULE PENALTY ₱500.00 | Actual: $nowStr]'
            : '[1ST OFFENSE: MISSED SCHEDULE FORMAL WARNING (₱0.00 WAIVED) | Actual: $nowStr]';
        processNotes = processNotes.isEmpty ? missedTag : '$missedTag | $processNotes';
      }
      if (_antiMortem == 'Separate Facility' && !processNotes.contains('SEPARATE FACILITY')) {
        final prefix =
            '[SEPARATE FACILITY - EMERGENCY SLAUGHTER | Cause: $_emergencyCause] Livestock arrived deceased due to non-infectious cause ($_emergencyCause). Routed to Separate Facility for immediate slaughter.';
        processNotes = processNotes.isEmpty ? prefix : '$prefix | $processNotes';
      }
      if (notifyDelay && delayReason.isNotEmpty) {
        processNotes = processNotes.isEmpty
            ? 'Technical delay ($nowStr): $delayReason'
            : '$processNotes | Technical delay ($nowStr): $delayReason';
      }

      final existing = await widget.supabase.from('slaughter_inspection').select('id').eq('request_id', reqId).maybeSingle();
      final inspectionData = <String, dynamic>{
        'request_id': reqId,
        'anti_mortem': isPartialAnteConfinement ? 'Passed' : _antiMortem,
        'process_stage': _processStage,
        'post_mortem': _isPartialPartCondemnation ? 'Partially Condemned' : _postMortem,
        'carcass_weight': double.tryParse(_carcassCtrl.text),
        'inspector_name': _inspectorCtrl.text,
        'process_notes': processNotes,
        'condemnation_reason': (_postMortem == 'Failed' || (isPartialBatch && !isPartialAnteConfinement)) ? _condemnationCtrl.text : null,
        'veterinary_findings': (_antiMortem == 'Failed' && !isPartialAnteConfinement) ? _notesCtrl.text : null,
        'ante_mortem_passed_at': ?resolvedAmPassedIso,
        if (isPartialAnteConfinement) ...{
          'passed_count': passedCount,
          'condemned_count': 0,
        } else if (isPartialBatch) ...{
          'passed_count': passedCount,
          'condemned_count': condemnedCount,
        },
      };

      Future<void> saveInspection(Map<String, dynamic> payload) async {
        if (existing != null) {
          await widget.supabase.from('slaughter_inspection').update(payload).eq('request_id', reqId);
        } else {
          await widget.supabase.from('slaughter_inspection').insert(payload);
        }
      }

      try {
        await saveInspection(inspectionData);
      } catch (_) {
        inspectionData.remove('ante_mortem_passed_at');
        inspectionData.remove('passed_count');
        inspectionData.remove('condemned_count');
        await saveInspection(inspectionData);
      }

      AuditLogService.instance.log(
        action: 'inspection_saved',
        module: 'Slaughter & Inspection',
        targetId: reqId?.toString(),
        targetRef: (widget.request['reference_no'] ?? 'REQ-$reqId').toString(),
        details: {
          'customer': widget.request['customer_name'] ?? '',
          'ante_mortem': inspectionData['anti_mortem'] ?? '',
          'post_mortem': inspectionData['post_mortem'] ?? '',
          'process_stage': inspectionData['process_stage'] ?? '',
          if (inspectionData['carcass_weight'] != null)
            'carcass_weight': inspectionData['carcass_weight'],
        },
      );

      // Safely dispatch customer notification without blocking the update (suppressed for on-site immediate slaughter walk-ins)
      if (!isImmediateSlaughterWalkIn && isPartialAnteConfinement) {
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final vetFindings = _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : 'Health issue detected during ante-mortem inspection';
        final parentRefNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

        dynamic confinedReqId = reqId;
        String? childRefNo;
        try {
          final childReq = await widget.supabase.from('requests').insert({
            'user_id': userId,
            'request_type': widget.request['request_type'],
            'customer_name': widget.request['customer_name'],
            'livestock_type': livestockType,
            'animal_count': condemnedCount,
            'province': widget.request['province'],
            'municipality': widget.request['municipality'],
            'barangay': widget.request['barangay'],
            'address': widget.request['address'],
            'market_stall_number': widget.request['market_stall_number'],
            'market_name': widget.request['market_name'],
            'preferred_date': widget.request['preferred_date'],
            'marking': widget.request['marking'],
            'special_instruction': '[CONFINED_FROM:$parentRefNo|days=$_confinementDays] $vetFindings',
            'barangay_certificate': widget.request['barangay_certificate'],
            'business_permit': widget.request['business_permit'],
            'proof_of_ownership': widget.request['proof_of_ownership'],
            'vet_certificate': widget.request['vet_certificate'],
            'status': 'anti_mortem_failed',
          }).select().single();

          confinedReqId = childReq['id'];
          childRefNo = 'MI-${DateTime.now().year}-${confinedReqId.toString().padLeft(3, '0')}';

          await widget.supabase.from('slaughter_inspection').insert({
            'request_id': confinedReqId,
            'anti_mortem': 'Failed',
            'process_stage': 'Confinement (${_confinementDays}d)',
            'post_mortem': 'Pending',
            'inspector_name': _inspectorCtrl.text,
            'veterinary_findings': vetFindings,
            'process_notes': 'Split from $parentRefNo for $_confinementDays-day confinement. $vetFindings',
          });
        } catch (e) {
          debugPrint('Split confinement request error: $e');
        }

        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: '$livestockType — Partial Confinement ($condemnedCount of $_totalHeads Confined)',
          message:
              'Ante-mortem inspection placed $condemnedCount of $_totalHeads head(s) in $_confinementDays-day facility confinement ($vetFindings). $passedCount healthy head(s) are proceeding to slaughter & dispatch.',
          type: 'anti_mortem_failed',
          data: {
            'request_id': confinedReqId,
            'livestock_type': livestockType,
            'veterinary_findings': vetFindings,
            'inspector_name': _inspectorCtrl.text,
            'animal_count': condemnedCount,
            'total_animal_count': _totalHeads,
            'passed_count': passedCount,
            'condemned_count': condemnedCount,
            'confinement_days': _confinementDays,
            'parent_ref': parentRefNo,
            'child_ref': ?childRefNo,
            'is_partial_confinement': true,
          },
        );
      } else if (!isImmediateSlaughterWalkIn && isPartialBatch) {
        final livestockType = widget.request['livestock_type'] ?? 'Livestock';
        final reason = _condemnationCtrl.text.trim().isNotEmpty
            ? _condemnationCtrl.text.trim()
            : (_notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : 'Health issue detected');
        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: '$livestockType — Partial Condemnation ($condemnedCount of $_totalHeads Condemned)',
          message:
              'Health issue detected on $condemnedCount of $_totalHeads head(s) ($reason). $passedCount healthy head(s) continue to processing. Please review the condemnation slip for the affected head(s).',
          type: 'post_mortem_failed',
          data: {
            'request_id': reqId,
            'customer_name': widget.request['customer_name'],
            'livestock_type': livestockType,
            'condemnation_reason': reason,
            'inspector_name': _inspectorCtrl.text,
            'animal_count': _totalHeads,
            'passed_count': passedCount,
            'condemned_count': condemnedCount,
            'carcass_weight': _carcassCtrl.text,
            'process_notes': processNotes,
          },
        );
      }
      if (!isImmediateSlaughterWalkIn && notifTitle != null && notifMessage != null && notifType != null) {
        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: notifTitle,
          message: notifMessage,
          type: notifType,
          data: notifData,
        );
      }

      // Notify Clerk / Admin via staff notification bell
      final staffRefNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
      final staffCust = widget.request['customer_name']?.toString().trim();
      final staffCustLabel = (staffCust != null && staffCust.isNotEmpty) ? staffCust : 'Customer';
      if (newStatus == 'releasable') {
        await StaffNotificationService.sendStaffNotification(
          targetRole: 'Clerk',
          type: 'ready_for_payment',
          title: 'Ready for Billing & Payment',
          message: '$staffRefNo ($staffCustLabel) passed inspection — ready for cashiering & payment.',
          requestId: (reqId as num).toInt(),
          referenceNo: staffRefNo,
          dedupKey: 'req_${reqId}_ready_for_payment',
        );
      } else if (newStatus == 'anti_mortem_failed' ||
          newStatus == 'post_mortem_failed' ||
          newStatus == 'condemned' ||
          newStatus == 'delay_error') {
        await StaffNotificationService.sendStaffNotification(
          targetRole: 'Admin',
          type: 'inspection_flagged',
          title: 'Inspection Flagged',
          message: '$staffRefNo ($staffCustLabel) marked as ${newStatus.replaceAll('_', ' ')}.',
          requestId: (reqId as num).toInt(),
          referenceNo: staffRefNo,
          dedupKey: 'req_${reqId}_flagged_$newStatus',
        );
      }

      // If missed schedule occurred, send dedicated Schedule Notice
      if (_isMissedSchedule) {
        final prefStr = widget.request['preferred_date']?.toString() ?? 'scheduled date';
        String schedDisplay = prefStr;
        try {
          schedDisplay = DateFormat('MMMM d, yyyy').format(DateTime.parse(prefStr));
        } catch (_) {}
        final refNum = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

        if (!isRepeatOffense) {
          await NotificationService.sendNotificationSafely(
            widget.supabase,
            userId: userId,
            title: '⚠️ Schedule Notice: 1st Offense Warning (Fee Waived)',
            message: 'You missed your reserved slaughter schedule for $refNum on $schedDisplay. Under Tabaco City abattoir guidelines, grace is granted for your 1st offense with ₱0.00 penalty. Please ensure livestock arrives on your scheduled date in future bookings, as repeat missed schedules will automatically incur a ₱500.00 Wasted Slot Penalty.',
            type: 'missed_schedule_warning',
            referenceNo: refNum,
            data: {
              'request_id': reqId,
              'reference_no': refNum,
              'offense_level': 1,
              'penalty_fee': 0.0,
              'is_warning_only': true,
              'scheduled_date': prefStr,
              'actual_date': nowStr,
            },
          );
        } else {
          await NotificationService.sendNotificationSafely(
            widget.supabase,
            userId: userId,
            title: '⛔ Missed Schedule Penalty Applied (₱500.00)',
            message: 'You missed your reserved slaughter schedule for $refNum on $schedDisplay. Having previously received a formal warning, an automatic ₱500.00 Wasted Slot Penalty has been charged to your bill (Repeat Offense #$offenseLevel).',
            type: 'missed_schedule_penalty',
            referenceNo: refNum,
            data: {
              'request_id': reqId,
              'reference_no': refNum,
              'offense_level': offenseLevel,
              'penalty_fee': 500.0,
              'is_warning_only': false,
              'scheduled_date': prefStr,
              'actual_date': nowStr,
            },
          );
        }
      }

      // Auto-send detailed Ante-Mortem Failed or Post-Mortem Failed SMS to walk-in customers
      // (same relevant details as mobile notifications, without sending the condemnation slip itself)
      String? walkInSmsFeedback;
      final walkInPhone = WalkInSmsService.resolveWalkInPhone(widget.request);
      final isWalkInFailure = walkInPhone.isNotEmpty &&
          !isImmediateSlaughterWalkIn &&
          (isPartialAnteConfinement ||
              _antiMortem == 'Failed' ||
              _postMortem == 'Failed' ||
              isPartialBatch);
      if (isWalkInFailure) {
        final isAnteFailSms = isPartialAnteConfinement ||
            (_antiMortem == 'Failed' && _postMortem != 'Failed' && !_healthIssueDetected);
        final smsStage = isAnteFailSms ? 'ante_mortem_failed' : 'post_mortem_failed';
        final smsFindings = isAnteFailSms
            ? (_notesCtrl.text.trim().isNotEmpty
                ? _notesCtrl.text.trim()
                : 'Health abnormality detected during ante-mortem inspection')
            : (_condemnationCtrl.text.trim().isNotEmpty
                ? _condemnationCtrl.text.trim()
                : (_notesCtrl.text.trim().isNotEmpty
                    ? _notesCtrl.text.trim()
                    : 'Health issue detected during post-mortem inspection'));
        final smsBody = WalkInSmsHelper.buildDefaultMessage(
          stage: smsStage,
          refNo: staffRefNo,
          customerName: staffCustLabel,
          marking: (widget.request['marking'] ?? '').toString(),
          livestockType: (widget.request['livestock_type'] ?? 'Livestock').toString(),
          animalCount: _totalHeads,
          findings: smsFindings,
          inspectorName: _inspectorCtrl.text.trim(),
          passedCount: (isPartialAnteConfinement || isPartialBatch) ? passedCount : null,
          condemnedCount: (isPartialAnteConfinement || isPartialBatch) ? condemnedCount : null,
          confinementDays: isPartialAnteConfinement ? _confinementDays : null,
        );
        final smsRes = await WalkInSmsService.sendSms(
          phone: walkInPhone,
          message: smsBody,
          stage: smsStage,
          refNo: staffRefNo,
          customerName: staffCustLabel,
          requestId: reqId?.toString(),
        );
        walkInSmsFeedback = smsRes.success
            ? 'Failure SMS sent to $walkInPhone'
            : 'Inspection saved (SMS notice: ${smsRes.message})';
      } else if (walkInPhone.isNotEmpty &&
          !isImmediateSlaughterWalkIn &&
          newStatus == 'releasable') {
        // Auto-send Bill Ready SMS when weighing & post-mortem complete for walk-in customers
        final weightStr = _carcassCtrl.text.trim();
        final isMarket = (widget.request['request_type'] ?? '').toString().toLowerCase() == 'market';
        final billSmsBody = WalkInSmsHelper.buildDefaultMessage(
          stage: 'bill_ready',
          refNo: staffRefNo,
          customerName: staffCustLabel,
          marking: (widget.request['marking'] ?? '').toString(),
          livestockType: (widget.request['livestock_type'] ?? 'Livestock').toString(),
          animalCount: _totalHeads,
          statusSummary: weightStr.isNotEmpty ? 'Carcass weight: $weightStr kg' : '',
          findings: isMarket
              ? 'Please settle payment at the Abattoir Cashier window to clear your meat for market delivery dispatch.'
              : 'Please settle payment at the Abattoir Cashier window before 5:00 PM to claim your meat carcass.',
        );
        final smsRes = await WalkInSmsService.sendSms(
          phone: walkInPhone,
          message: billSmsBody,
          stage: 'bill_ready',
          refNo: staffRefNo,
          customerName: staffCustLabel,
          requestId: reqId?.toString(),
        );
        walkInSmsFeedback = smsRes.success
            ? 'Bill-ready SMS sent to $walkInPhone'
            : 'Inspection saved (SMS notice: ${smsRes.message})';
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              walkInSmsFeedback != null
                  ? 'Process updated • $walkInSmsFeedback'
                  : 'Process updated successfully',
            ),
            backgroundColor: Colors.green.shade600,
          ),
        );
        // Auto-show Condemnation Slip only when post-mortem failed (Partial or Whole)
        if (_postMortem == 'Failed') {
          final ctx = context;
          final slipReq = {
            ...widget.request,
            if (isPartialBatch) ...{
              'passed_count': passedCount,
              'condemned_count': condemnedCount,
            },
          };
          final isPartialSlip = _isPartialPartCondemnation;
          final slipWeight = isPartialSlip &&
                  _condemnedWeightCtrl.text.trim().isNotEmpty &&
                  _condemnedWeightCtrl.text.trim() != '0'
              ? _condemnedWeightCtrl.text.trim()
              : _carcassCtrl.text;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (ctx.mounted) {
              showDialog(
                context: ctx,
                builder: (_) => _CondemnationSlipDialog(
                  request: slipReq,
                  condemnationReason: _condemnationCtrl.text,
                  inspectorName: _inspectorCtrl.text,
                  carcassWeight: slipWeight,
                  supabase: widget.supabase,
                  isPartialCondemnation: isPartialSlip,
                  slipNumber: _condemnationSlipNo,
                  onDone: widget.onDone,
                ),
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = 'MI-${DateTime.now().year}-${widget.request['id'].toString().padLeft(3, '0')}';
    final cust = widget.request['customer_name']?.toString() ?? 'Unknown';
    final type = widget.request['request_type'] == 'market' ? 'Market' : 'Barangay';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Update Slaughter Process', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Update the process stage and inspection results.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              if (widget.request['animals_in_lot'] is List &&
                  (widget.request['animals_in_lot'] as List).isNotEmpty) ...[
                const SizedBox(height: 14),
                AnimalsInLotReadOnlyList(
                  rawAnimalsInLot: widget.request['animals_in_lot'],
                  fallbackCount: (widget.request['animal_count'] as num?)?.toInt() ?? 1,
                  fallbackOrigin: (widget.request['barangay'] ?? widget.request['municipality'] ?? 'Tabaco City').toString(),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _buildLabelValue('Reference Number', ref)),
                  Expanded(child: _buildLabelValue('Customer', cust)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _buildLabelValue('Request Type', type)),
                  Expanded(
                    child: _buildLabelValue(
                      'Livestock Tag / Marking',
                      widget.request['marking']?.toString().isNotEmpty == true
                          ? widget.request['marking'].toString()
                          : '—',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              Builder(
                builder: (_) {
                  final cleanedInstr = (widget.request['special_instruction'] ?? '')
                      .toString()
                      .replaceAll('[WALK_IN]', '')
                      .trim();
                  if (cleanedInstr.isEmpty) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.speaker_notes, color: Color(0xFFB45309), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Customer Special Instructions:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                cleanedInstr,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF78350F),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              
              const Text('Ante-Mortem Result', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _antiMortem,
                    items: ['Pending', 'Passed', 'Failed', 'Separate Facility'].map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(
                        e == 'Separate Facility'
                            ? 'Separate Facility (Died in Transit — Non-Infectious)'
                            : e,
                        style: TextStyle(
                          fontWeight: e == 'Separate Facility' ? FontWeight.bold : FontWeight.normal,
                          color: e == 'Separate Facility' ? const Color(0xFFC2410C) : Colors.black87,
                        ),
                      ),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _antiMortem = v;
                          _checkAutoDetermination();
                        });
                      }
                    },
                  ),
                ),
              ),
              if (_antiMortem == 'Separate Facility') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEA580C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bolt_rounded, color: Color(0xFFC2410C), size: 18),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Separate Facility — Immediate Slaughter (Bypassing Standard Floor Stages)',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF9A3412)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Livestock arrived deceased due to stress, heat stroke, or accidental (non-infectious) causes. Enter Carcass Weight & Post-Mortem result to complete.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFFC2410C), height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Non-Infectious Cause of Death *',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9A3412)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _emergencyCause,
                            items: _emergencyCauses
                                .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _emergencyCause = v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Process Stage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _processStage,
                              items: const [
                                'Separate Facility (Weighing)',
                                'Ante-Mortem',
                                'Preparation',
                                'Stunning',
                                'Bleeding',
                                'Scalding/Dehairing',
                                'Evisceration',
                                'Post-Mortem Inspection',
                                'Weighing',
                                'Complete',
                                'Technical Error/Delay',
                              ].map((e) => DropdownMenuItem(
                                value: e,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: e == 'Technical Error/Delay' ? Colors.redAccent : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(e, style: TextStyle(color: e == 'Technical Error/Delay' ? Colors.white : Colors.black87)),
                                ),
                              )).toList(),
                              onChanged: _antiMortem == 'Pending'
                                  ? null
                                  : (v) => setState(() {
                                        if (v == 'Complete') {
                                          final weight = double.tryParse(_carcassCtrl.text.trim());
                                          if (weight == null || weight <= 0) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Warning: Carcass weight is required before marking as Complete.'),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                            _processStage = 'Weighing';
                                            return;
                                          }
                                        }
                                        _processStage = v!;
                                        if (_processStage == 'Complete' && _postMortem == 'Pending') {
                                          _postMortem = 'Passed';
                                        }
                                      }),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _antiMortem == 'Pending'
                              ? 'Locked at Ante-Mortem until Ante-Mortem Result is marked Passed.'
                              : (_antiMortem == 'Passed' && _processStage != 'Complete'
                                  ? 'Auto-advances every 5 mins: Stunning → Bleeding → Scalding/Dehairing → Evisceration.'
                                  : 'Reflects active inspection or weighing stage.'),
                          style: TextStyle(
                            fontSize: 11,
                            color: _antiMortem == 'Pending'
                                ? const Color(0xFF64748B)
                                : const Color(0xFF0F5132),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Carcass Weight (kg)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _carcassCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            hintText: 'e.g. 75.0',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Builder(
                          builder: (context) {
                            final count = _effectivePassedCount > 0 ? _effectivePassedCount : _totalHeads;
                            final type = widget.request['livestock_type']?.toString() ?? 'Livestock';
                            final range = _getAcceptableWeightRange(type, count);
                            final w = double.tryParse(_carcassCtrl.text.trim());
                            if (w == null) {
                              return Text(
                                'Acceptable range: ${range.$1.toStringAsFixed(0)}–${range.$2.toStringAsFixed(0)} kg ($count head $type)',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              );
                            }
                            final inRange = _isWeightInRange(w, type, count);
                            return Row(
                              children: [
                                Icon(
                                  inRange ? Icons.check_circle_outline : Icons.info_outline,
                                  size: 13,
                                  color: inRange ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    inRange
                                        ? 'Within acceptable range (${range.$1.toStringAsFixed(0)}–${range.$2.toStringAsFixed(0)} kg)'
                                        : 'Outside typical range (${range.$1.toStringAsFixed(0)}–${range.$2.toStringAsFixed(0)} kg)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: inRange ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Post-Mortem Result', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _postMortem,
                              items: ['Pending', 'Passed', 'Failed'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _postMortem = v;
                                    if (v == 'Failed') {
                                      _healthIssueDetected = _resolvedCondemnationType == 'Whole Condemnation';
                                    } else {
                                      _healthIssueDetected = false;
                                    }
                                    _checkAutoDetermination();
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Inspector Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
                        const SizedBox(height: 6),
                        _buildInspectorField(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Process Notes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
              const SizedBox(height: 6),
              TextField(
                controller: _notesCtrl,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: const [SentencesCapitalizationFormatter()],
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),

              if (_totalHeads >= 2 && _hasHealthFailure) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFB923C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.splitscreen_outlined, size: 18, color: Color(0xFFC2410C)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Batch Health Issue Breakdown (2+ Heads)',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF9A3412)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _effectivePassedCount > 0
                            ? (_antiMortem == 'Failed' && _postMortem != 'Failed' && !_healthIssueDetected
                                ? '$_effectivePassedCount healthy head(s) will proceed to immediate slaughter & dispatch; $_condemnedCount affected head(s) will be split into a $_confinementDays-day confinement record.'
                                : '$_effectivePassedCount healthy head(s) will proceed to weighing, MIC, and payment; $_condemnedCount affected head(s) will receive a Condemnation Slip.')
                            : 'All $_totalHeads head(s) are marked failed/condemned.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412), height: 1.35),
                      ),
                      if (_antiMortem == 'Failed' && _postMortem != 'Failed' && !_healthIssueDetected && _effectivePassedCount > 0) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text(
                              'Confinement Period:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7C2D12)),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('1 Day', style: TextStyle(fontSize: 11.5)),
                              selected: _confinementDays == 1,
                              selectedColor: const Color(0xFFFED7AA),
                              onSelected: (_) => setState(() => _confinementDays = 1),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('2 Days', style: TextStyle(fontSize: 11.5)),
                              selected: _confinementDays == 2,
                              selectedColor: const Color(0xFFFED7AA),
                              onSelected: (_) => setState(() => _confinementDays = 2),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Affected / Failed Heads', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7C2D12))),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFFDBA74)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      isExpanded: true,
                                      value: _condemnedCount.clamp(1, _totalHeads),
                                      items: List.generate(_totalHeads, (i) => i + 1)
                                          .map((n) => DropdownMenuItem(value: n, child: Text('$n of $_totalHeads head(s)')))
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            _condemnedCount = val;
                                            _checkAutoDetermination();
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: _effectivePassedCount > 0 ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _effectivePassedCount > 0 ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Healthy / Passed Heads', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$_effectivePassedCount head(s)',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: _effectivePassedCount > 0 ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              // Condemnation Slip Section — hidden until Post-Mortem Result is set to Failed
              if (_postMortem == 'Failed') ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isPartialPartCondemnation
                        ? const Color(0xFFFFFBEB)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isPartialPartCondemnation
                          ? const Color(0xFFFDE68A)
                          : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isPartialPartCondemnation
                                ? Icons.content_cut_rounded
                                : Icons.report_gmailerrorred_rounded,
                            size: 18,
                            color: _isPartialPartCondemnation
                                ? const Color(0xFFB45309)
                                : const Color(0xFFB91C1C),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isPartialPartCondemnation
                                  ? 'Partial Condemnation Slip ($_condemnationSlipNo)'
                                  : 'Whole Condemnation Slip ($_condemnationSlipNo)',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: _isPartialPartCondemnation
                                    ? const Color(0xFF92400E)
                                    : const Color(0xFF991B1B),
                              ),
                            ),
                          ),
                          if (_condemnationSlipGenerated)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF86EFAC)),
                              ),
                              child: const Text(
                                'Slip Ready',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF166534),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isPartialPartCondemnation
                            ? 'Enter the total carcass weight above and the condemned part weight below — Payment & Cashiering will automatically deduct the condemned part weight and bill only the non-condemned portion.'
                            : 'The entire carcass is condemned and blocked from dispatch. A Whole Condemnation Slip will be generated automatically upon saving.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: _isPartialPartCondemnation
                              ? const Color(0xFF92400E)
                              : const Color(0xFF991B1B),
                        ),
                      ),
                      const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 540;
                        final typeDropdown = DropdownButtonFormField<String>(
                          key: ValueKey(_resolvedCondemnationType),
                          initialValue: _resolvedCondemnationType,
                          isExpanded: true,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF0F5132), width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF0F5132), width: 1.8),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Partial Condemnation', child: Text('Partial Condemnation', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'Whole Condemnation', child: Text('Whole Condemnation', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _condemnationType = v;
                                _healthIssueDetected = (v == 'Whole Condemnation');
                                if (v == 'Whole Condemnation' && _condemnedPartCtrl.text.trim().isEmpty) {
                                  _condemnedPartCtrl.text = 'Whole Carcass';
                                } else if (v == 'Partial Condemnation' && _condemnedPartCtrl.text.trim() == 'Whole Carcass') {
                                  _condemnedPartCtrl.clear();
                                }
                                _checkAutoDetermination();
                              });
                            }
                          },
                        );

                        final partField = TextField(
                          controller: _condemnedPartCtrl,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            hintText: 'Condemned part (e.g., Liver, Lungs)',
                            hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF0F5132), width: 1.5),
                            ),
                          ),
                        );

                        final weightField = TextField(
                          controller: _condemnedWeightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            hintText: '0',
                            suffixText: 'kg',
                            suffixStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF0F5132), width: 1.5),
                            ),
                          ),
                        );

                        final reasonField = TextField(
                          controller: _condemnationReasonCtrl,
                          textCapitalization: TextCapitalization.sentences,
                          inputFormatters: const [SentencesCapitalizationFormatter()],
                          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            hintText: 'Reason (e.g., Pneumonia, Bruising)',
                            hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF0F5132), width: 1.5),
                            ),
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            children: [
                              Row(children: [Expanded(child: typeDropdown), const SizedBox(width: 8), Expanded(child: partField)]),
                              const SizedBox(height: 8),
                              Row(children: [Expanded(flex: 2, child: weightField), const SizedBox(width: 8), Expanded(flex: 3, child: reasonField)]),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(flex: 3, child: typeDropdown),
                            const SizedBox(width: 10),
                            Expanded(flex: 3, child: partField),
                            const SizedBox(width: 10),
                            Expanded(flex: 2, child: weightField),
                            const SizedBox(width: 10),
                            Expanded(flex: 3, child: reasonField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _handleGenerateCondemnationSlip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF97316),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Generate Condemnation Slip ($_condemnationSlipNo)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              ],

              // Auto-Detected Missed Schedule Banner (shown read-only only when past 5:00 PM cutoff)
              if (_isMissedSchedule) ...[
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final schedPref = widget.request['preferred_date']?.toString();
                    String schedDisplay = 'scheduled date';
                    if (schedPref != null && schedPref.isNotEmpty) {
                      try {
                        schedDisplay = DateFormat('MMMM d, yyyy').format(DateTime.parse(schedPref));
                      } catch (_) {
                        schedDisplay = schedPref;
                      }
                    }
                    final bool isRepeat = _customerPriorMissedCount >= 1;
                    final Color cardBg = isRepeat ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);
                    final Color cardBorder = isRepeat ? const Color(0xFFEF4444) : const Color(0xFFFDE68A);
                    final Color primaryTextColor = isRepeat ? const Color(0xFF991B1B) : const Color(0xFF92400E);

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isRepeat ? Icons.event_busy : Icons.schedule_rounded,
                                size: 18,
                                color: primaryTextColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isRepeat
                                      ? 'Auto Missed Schedule (Repeat Offense #${_customerPriorMissedCount + 1} — ₱500.00 Penalty)'
                                      : 'Auto Missed Schedule (1st Offense — Formal Warning)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: primaryTextColor,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isRepeat ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isRepeat ? const Color(0xFFFCA5A5) : const Color(0xFFFCD34D),
                                  ),
                                ),
                                child: Text(
                                  isRepeat ? '₱500.00 Auto' : '₱0.00 Waived',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isRepeat ? const Color(0xFFB91C1C) : const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isRepeat
                                ? 'Automatically flagged past the 5:00 PM cutoff for $schedDisplay. Because this customer has $_customerPriorMissedCount prior violation(s), the ₱500.00 Wasted Slot Penalty is automatically added to their cashiering bill.'
                                : 'Automatically flagged past the 5:00 PM cutoff for $schedDisplay. 1st offense grace applies (₱0.00 penalty) with an automatic formal warning sent to the customer.',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.35),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)),
                    child: const Text('Cancel', style: TextStyle(color: Colors.black87)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : () => _updateProcess(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F5132),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Update Process', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabelValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildInspectorField() {
    // If only one inspector is configured in the system, show automatically with no other options
    if (_inspectors.length <= 1) {
      final name = _selectedInspector ?? (_inspectors.isNotEmpty ? _inspectors.first : 'Dr. Maria Clara Reyes');
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF2D6A4F)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2D3748),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F9F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Inspector',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A8C62),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // If multiple inspectors (e.g. 2, 3, or more) are configured, all are available for selection
    final currentValue = _inspectors.contains(_selectedInspector)
        ? _selectedInspector
        : _inspectors.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: currentValue,
          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF4A5568)),
          items: _inspectors.map((inspectorName) {
            return DropdownMenuItem<String>(
              value: inspectorName,
              child: Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: Color(0xFF2D6A4F)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      inspectorName,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedInspector = val;
                _inspectorCtrl.text = val;
              });
            }
          },
        ),
      ),
    );
  }
}

class _MICDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final SupabaseClient supabase;
  final VoidCallback onDone;

  const _MICDialog({
    required this.request,
    required this.supabase,
    required this.onDone,
  });

  @override
  State<_MICDialog> createState() => _MICDialogState();
}

class _MICDialogState extends State<_MICDialog> {
  bool _isPrinting = false;

  Future<void> _printAndProcessMIC() async {
    setState(() => _isPrinting = true);
    try {
      final passedCount = int.tryParse(widget.request['passed_count']?.toString() ?? '');
      final micRequest = (passedCount != null && passedCount > 0)
          ? {...widget.request, 'animal_count': passedCount}
          : widget.request;
      final pdfBytes = await InspectionDocumentsPdfGenerator.generateMIC(
        request: micRequest,
      );
      final reqId = widget.request['id'];
      final certNo = 'MIC-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // 1. Open print page
      await Printing.layoutPdf(
        name: 'MIC_$certNo.pdf',
        onLayout: (format) async => pdfBytes,
      );

      // 2. Automatically update database status to mic_generated if not already paid or released
      final currentStatus = widget.request['status']?.toString();
      final isAlreadyReleased = currentStatus == 'released' || widget.request['released_at'] != null;
      final isAlreadyPaid = currentStatus == 'paid';

      if (!isAlreadyReleased && !isAlreadyPaid) {
        await widget.supabase.from('requests').update({
          'status': 'mic_generated',
        }).eq('id', reqId);

        final staffRefNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';
        final staffCust = widget.request['customer_name']?.toString().trim();
        final staffCustLabel = (staffCust != null && staffCust.isNotEmpty) ? staffCust : 'Customer';
        await StaffNotificationService.sendStaffNotification(
          targetRole: 'Clerk',
          type: 'ready_for_payment',
          title: 'Ready for Billing & Payment',
          message: '$staffRefNo ($staffCustLabel) MIC issued — ready for cashiering & payment.',
          requestId: (reqId as num).toInt(),
          referenceNo: staffRefNo,
          dedupKey: 'req_${reqId}_ready_for_payment',
        );
      }

      final existing = await widget.supabase.from('slaughter_inspection').select('id, process_notes').eq('request_id', reqId).maybeSingle();
      if (existing != null) {
        String notes = (existing['process_notes'] ?? '').toString();
        if (!notes.contains('[COMPLETED_AT:')) {
          final completedTag = '[COMPLETED_AT:${DateTime.now().toUtc().toIso8601String()}]';
          notes = notes.isEmpty ? completedTag : '$completedTag | $notes';
        }
        if (!notes.contains('MIC Generated')) {
          notes = notes.isEmpty ? 'MIC Generated' : '$notes | MIC Generated';
        }
        await widget.supabase.from('slaughter_inspection').update({
          'process_stage': 'Complete',
          'process_notes': notes,
        }).eq('request_id', reqId);
      }

      // 3. Notify customer safely (suppressed for on-site immediate slaughter walk-ins)
      final isImmediateOnSite = (widget.request['anti_mortem']?.toString() == 'Separate Facility') ||
          (widget.request['process_notes'] ?? '').toString().contains('SEPARATE FACILITY');
      final userId = widget.request['user_id']?.toString() ?? widget.request['customer_id']?.toString();
      if (!isImmediateOnSite && userId != null && userId.isNotEmpty) {
        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: 'Meat Inspection Certificate Ready',
          message: 'Your Meat Inspection Certificate ($certNo) has been issued and printed. Meat is ready for releasing.',
          type: 'mic_generated',
          data: {
            'request_id': reqId,
            'certificate_number': certNo,
            'status': 'mic_generated',
          },
        );
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Meat Inspection Certificate ($certNo) printed and marked as processed!'),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing MIC: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final certNo = 'MIC-${DateTime.now().year}-${widget.request['id'].toString().padLeft(3, '0')}';
    final refNo = 'MI-${DateTime.now().year}-${widget.request['id'].toString().padLeft(3, '0')}';
    final customerName = widget.request['customer_name']?.toString() ?? '—';
    final livestock = widget.request['livestock_type']?.toString() ?? '—';
    final slaughterDate = widget.request['rescheduled_date'] ?? widget.request['preferred_date'];
    
    final antiMortem = widget.request['anti_mortem']?.toString().toUpperCase() ?? 'PENDING';
    final postMortem = widget.request['post_mortem']?.toString().toUpperCase() ?? 'PENDING';
    final inspector = widget.request['inspector_name']?.toString() ?? '—';

    String formatDate(dynamic v) {
      if (v == null) return '—';
      try {
        return DateFormat('dd/MM/yyyy').format(DateTime.parse(v.toString()));
      } catch (_) {
        return v.toString();
      }
    }

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/logo1.png', width: 70, height: 70, errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 70)),
                  const Text('MEAT INSPECTION CERTIFICATE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Image.asset('assets/images/logo2.png', width: 70, height: 70, errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 70)),
                ],
              ),
              const SizedBox(height: 32),
              Text('Certificated Number: $certNo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text('Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 24),
              Text('Customer: $customerName', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Text('Reference Number: $refNo', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Text('Livestock Type: $livestock', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              Text('Slaughter Date: ${formatDate(slaughterDate)}', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 32),
              Text('ANTE-MORTEM INSPECTION: $antiMortem', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text('POST-MORTEM INSPECTION: $postMortem', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text('Inspector: $inspector', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 32),
              const Text(
                'This Certificate of Inspection and Approval verifies that the meat '
                'product has undergone a comprehensive and systematic examination. '
                'The findings confirm that the product fully adheres to all prescribed '
                'health and sanitation standards, food safety regulations, and quality '
                'controls currently in effect. Consequently, this approval is granted, '
                'certifying the meat as fit for consumption by the general public.',
                style: TextStyle(height: 1.6, fontSize: 14),
                textAlign: TextAlign.justify,
              ),
              const SizedBox(height: 32),
              const Text('Facility: Tabaco City Slaughterhouse', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 40),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _isPrinting ? null : _printAndProcessMIC,
                  icon: _isPrinting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print, size: 18, color: Colors.white),
                  label: Text(_isPrinting ? 'Printing...' : 'Print', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CondemnationSlipDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final String condemnationReason;
  final String inspectorName;
  final String carcassWeight;
  final SupabaseClient supabase;
  final VoidCallback onDone;
  final bool isPartialCondemnation;
  final String? slipNumber;

  const _CondemnationSlipDialog({
    required this.request,
    required this.condemnationReason,
    required this.inspectorName,
    required this.carcassWeight,
    required this.supabase,
    required this.onDone,
    this.isPartialCondemnation = false,
    this.slipNumber,
  });

  @override
  State<_CondemnationSlipDialog> createState() => _CondemnationSlipDialogState();
}

class _CondemnationSlipDialogState extends State<_CondemnationSlipDialog> {
  bool _isPrinting = false;

  Future<void> _printAndProcessCondemnationSlip() async {
    setState(() => _isPrinting = true);
    try {
      final condemnedCount = int.tryParse(widget.request['condemned_count']?.toString() ?? '');
      final passedCount = int.tryParse(widget.request['passed_count']?.toString() ?? '');
      final isPartialBatch = condemnedCount != null && condemnedCount > 0 && passedCount != null && passedCount > 0;
      final slipRequest = isPartialBatch
          ? {...widget.request, 'animal_count': condemnedCount}
          : widget.request;

      final pdfBytes = await InspectionDocumentsPdfGenerator.generateCondemnationSlip(
        request: slipRequest,
        condemnationReason: widget.condemnationReason,
        inspectorName: widget.inspectorName,
        carcassWeight: widget.carcassWeight,
      );
      final reqId = widget.request['id'];
      final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // 1. Open print page
      await Printing.layoutPdf(
        name: 'Condemnation_Slip_$refNo.pdf',
        onLayout: (format) async => pdfBytes,
      );

      // 2. Persist condemnation details (only mark entire request condemned if NOT partial)
      final existing = await widget.supabase.from('slaughter_inspection').select('id').eq('request_id', reqId).maybeSingle();
      if (widget.isPartialCondemnation) {
        if (existing != null) {
          await widget.supabase.from('slaughter_inspection').update({
            'condemnation_reason': widget.condemnationReason,
          }).eq('request_id', reqId);
        } else {
          await widget.supabase.from('slaughter_inspection').insert({
            'request_id': reqId,
            'condemnation_reason': widget.condemnationReason,
          });
        }
      } else if (!isPartialBatch) {
        await widget.supabase.from('requests').update({
          'status': 'condemned',
        }).eq('id', reqId);

        if (existing != null) {
          await widget.supabase.from('slaughter_inspection').update({
            'post_mortem': 'Failed',
            'process_stage': 'Post-Mortem Inspection',
            'condemnation_reason': widget.condemnationReason,
          }).eq('request_id', reqId);
        } else {
          await widget.supabase.from('slaughter_inspection').insert({
            'request_id': reqId,
            'post_mortem': 'Failed',
            'process_stage': 'Post-Mortem Inspection',
            'condemnation_reason': widget.condemnationReason,
          });
        }
      }

      // 3. Notify customer safely
      final userId = widget.request['user_id']?.toString() ?? widget.request['customer_id']?.toString();
      if (userId != null && userId.isNotEmpty) {
        final livestock = widget.request['livestock_type'] ?? 'Livestock';
        final slipLabel = widget.slipNumber != null ? ' (${widget.slipNumber})' : '';
        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: widget.isPartialCondemnation
              ? 'Partial Condemnation Slip Issued$slipLabel'
              : 'Slaughter Condemned — Condemnation Slip Issued',
          message: widget.isPartialCondemnation
              ? 'A partial condemnation slip$slipLabel was recorded for your $livestock (${widget.condemnationReason}). The remaining passed carcass continues normal processing.'
              : 'A condemnation slip has been issued for your livestock ($livestock). The slaughter operation has been concluded.',
          type: 'condemnation_slip',
          data: {
            'request_id': reqId,
            'condemnation_reason': widget.condemnationReason,
            'status': widget.isPartialCondemnation ? 'partial_condemnation' : 'condemned',
          },
        );
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isPartialCondemnation
                  ? 'Partial condemnation slip${widget.slipNumber != null ? " (${widget.slipNumber})" : ""} printed & recorded!'
                  : 'Condemnation slip printed and operation marked concluded!',
            ),
            backgroundColor: const Color(0xFF2D6A4F),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing slip: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerName = widget.request['customer_name']?.toString() ?? '—';
    final livestock = widget.request['livestock_type']?.toString() ?? '—';
    final animalCount = widget.request['animal_count']?.toString() ?? '—';
    final dateNow = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final timeNow = DateFormat('hh:mm a').format(DateTime.now());

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 650,
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header with logos
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/logo1.png', width: 60, height: 60,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 60)),
                  const Column(
                    children: [
                      Text('Republic of the Philippines', style: TextStyle(fontSize: 12)),
                      Text('Province of Albay', style: TextStyle(fontSize: 12)),
                      Text('CITY OF TABACO', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Image.asset('assets/images/logo2.png', width: 60, height: 60,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 60)),
                ],
              ),
              const SizedBox(height: 20),

              // Info fields
              Row(
                children: [
                  Expanded(
                    child: _infoLine('Name of Establishment:', 'Tabaco City Slaughterhouse'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _infoLine('City:', 'Tabaco City')),
                  const SizedBox(width: 16),
                  Expanded(child: _infoLine('Province:', 'Albay')),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _infoLine('Date:', dateNow)),
                  const SizedBox(width: 16),
                  Expanded(child: _infoLine('Time:', timeNow)),
                ],
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'CONDEMNATION SLIP',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
              const SizedBox(height: 16),

              // Legal text
              const Text(
                'Pursuant to Republic Act No. 7394, otherwise known as the Consumer Act of the Philippines '
                'under Article 10 and 17; and Republic Act 9296 "The Meat Inspection Code of the Philippines" and '
                'the Department of Agriculture Administrative Order No. 7, Rules, and Regulations of RA 9296 series '
                'of 2005; and NMIS Administrative Order No. 6 the following meat/meat products/processed meat is '
                'hereby condemned.',
                style: TextStyle(fontSize: 11, height: 1.5),
                textAlign: TextAlign.justify,
              ),
              const SizedBox(height: 20),

              // Table
              Table(
                border: TableBorder.all(color: Colors.black87, width: 1),
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFF5F5F5)),
                    children: [
                      _tableHeader('FOOD ANIMAL/MEAT/MEAT\nPRODUCTS/PROCESS MEAT'),
                      _tableHeader('QUANTITY/WEIGHT'),
                      _tableHeader('CAUSE OF CONDEMNATION'),
                    ],
                  ),
                  TableRow(
                    children: [
                      _tableCell(livestock),
                      _tableCell('$animalCount head(s)${widget.carcassWeight.isNotEmpty ? '\n${widget.carcassWeight}kg' : ''}'),
                      _tableCell(widget.condemnationReason.isNotEmpty ? widget.condemnationReason : '—'),
                    ],
                  ),
                  // Empty rows for additional entries
                  TableRow(children: [_tableCell(''), _tableCell(''), _tableCell('')]),
                  TableRow(children: [_tableCell(''), _tableCell(''), _tableCell('')]),
                ],
              ),
              const SizedBox(height: 28),

              // Signatures
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Condemned by:', style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 28),
                        Container(
                          width: 200,
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black54))),
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(widget.inspectorName.isNotEmpty ? widget.inspectorName : '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        const Text('Veterinarian/Meat Control Officer/Meat Inspector', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500)),
                        const Text('(Signature Over Printed Name)', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Conforme:', style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 28),
                        Container(
                          width: 200,
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black54))),
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(customerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        const Text('Name of Owner/Representative', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500)),
                        const Text('(Signature Over Printed Name)', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Disposed by / Witness
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Disposed by:', style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 28),
                        Container(
                          width: 200,
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black54))),
                          padding: const EdgeInsets.only(bottom: 2),
                        ),
                        const Text('Veterinarian/Meat Control Officer/Meat Inspector', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500)),
                        const Text('(Signature Over Printed Name)', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Witness:', style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 28),
                        Container(
                          width: 200,
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black54))),
                          padding: const EdgeInsets.only(bottom: 2),
                        ),
                        const Text('(Signature Over Printed Name)', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Print button
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _isPrinting ? null : _printAndProcessCondemnationSlip,
                  icon: _isPrinting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.print, size: 18, color: Colors.white),
                  label: Text(_isPrinting ? 'Printing...' : 'Print', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black54))),
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ),
      ],
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
    );
  }

  Widget _tableCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  ANTE-MORTEM RESPONSE DIALOG
//  Admin handles the customer's response (confine or take back)
// ═══════════════════════════════════════════════════════════
class _AntiMortemResponseDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  final SupabaseClient supabase;
  final VoidCallback onDone;

  const _AntiMortemResponseDialog({
    required this.request,
    required this.supabase,
    required this.onDone,
  });

  @override
  State<_AntiMortemResponseDialog> createState() => _AntiMortemResponseDialogState();
}

class _AntiMortemResponseDialogState extends State<_AntiMortemResponseDialog> {
  bool _isLoading = false;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final _notesCtrl = TextEditingController();
  late String _manualDecision;

  bool get _isTechnicalDelay {
    final status = widget.request['status']?.toString();
    final stage = widget.request['process_stage']?.toString();
    final insp = widget.request['slaughter_inspection'];
    String? inspStage;
    if (insp is Map) inspStage = insp['process_stage']?.toString();
    return status == 'delay_error' ||
        stage == 'Technical Error/Delay' ||
        inspStage == 'Technical Error/Delay';
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.request['anti_mortem_response']?.toString() ?? '';
    if (existing.isNotEmpty) {
      _manualDecision = existing;
    } else {
      _manualDecision = _isTechnicalDelay ? 'accept_penalty' : 'confine';
    }
  }

  String get _response {
    final existing = widget.request['anti_mortem_response']?.toString() ?? '';
    return existing.isNotEmpty ? existing : _manualDecision;
  }

  bool get _hasCustomerAppResponse =>
      (widget.request['anti_mortem_response']?.toString() ?? '').isNotEmpty;
  bool get _isPenaltyAccepted => _isTechnicalDelay && _response == 'accept_penalty';
  // Failed ante-mortem animals cannot be taken back; mandatory 2-day confinement always applies.
  bool get _isConfine => !_isTechnicalDelay;
  bool get _isTakeBack => _isTechnicalDelay && _response == 'take_back';

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (time != null) setState(() => _selectedTime = time);
  }

  Future<void> _markDelayResolvedAndReleasable() async {
    setState(() => _isLoading = true);
    try {
      final reqId = widget.request['id'];
      final userId = widget.request['user_id'];
      final livestockType = widget.request['livestock_type'] ?? 'Livestock';
      final animalCount = widget.request['animal_count'] ?? 1;
      final refNo = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

      // 1. Update request status to releasable
      await widget.supabase.from('requests').update({
        'status': 'releasable',
      }).eq('id', reqId);

      // 2. Update slaughter_inspection to Complete & Passed
      final existing = await widget.supabase.from('slaughter_inspection').select('id').eq('request_id', reqId).maybeSingle();
      final defaultInspector = AppSettingsService.instance.configuredInspectors.isNotEmpty
          ? AppSettingsService.instance.configuredInspectors.first
          : 'Dr. Maria Clara Reyes';
      final existingInsp = widget.request['inspector_name']?.toString().trim();
      final resolvedInsp = (existingInsp != null && existingInsp.isNotEmpty) ? existingInsp : defaultInspector;

      final inspectionData = {
        'request_id': reqId,
        'anti_mortem': 'Passed',
        'process_stage': 'Complete',
        'post_mortem': 'Passed',
        'inspector_name': resolvedInsp,
        'process_notes': _notesCtrl.text.isNotEmpty
            ? _notesCtrl.text
            : 'Technical delay resolved. Resumed slaughter completed successfully.',
      };
      if (existing != null) {
        await widget.supabase.from('slaughter_inspection').update(inspectionData).eq('request_id', reqId);
      } else {
        await widget.supabase.from('slaughter_inspection').insert(inspectionData);
      }

      // 3. Notify customer
      final isMarketOrder = (widget.request['request_type'] ?? '').toString().toLowerCase() == 'market';
      final delayTitle = isMarketOrder
          ? '$livestockType — Slaughter Complete & Ready for Delivery'
          : '$livestockType — Slaughter Complete & Ready for Collection';
      final delayMessage = isMarketOrder
          ? 'Your $animalCount head(s) of $livestockType ($refNo) slaughter has resumed and completed successfully. Market delivery is scheduled — please settle payment via GCash or cashier to clear your carcass for delivery dispatch.'
          : 'Your $animalCount head(s) of $livestockType ($refNo) slaughter has resumed and completed successfully. Under Cash-on-Pickup, please settle payment at the cashier counter upon arrival before carcass handover. Reminder: Claim before 5:00 PM to avoid cold storage preservation fees.';

      await NotificationService.sendNotificationSafely(
        widget.supabase,
        userId: userId,
        title: delayTitle,
        message: delayMessage,
        type: 'slaughter_completed',
        data: {
          'request_id': reqId,
          'livestock_type': livestockType,
          'penalty_fee': (widget.request['penalty_fee'] != null && (double.tryParse(widget.request['penalty_fee'].toString()) ?? 0.0) > 0)
              ? (double.tryParse(widget.request['penalty_fee'].toString()) ?? 500.0)
              : 0.0,
        },
      );

      final staffCust = widget.request['customer_name']?.toString().trim();
      final staffCustLabel = (staffCust != null && staffCust.isNotEmpty) ? staffCust : 'Customer';
      await StaffNotificationService.sendStaffNotification(
        targetRole: 'Clerk',
        type: 'ready_for_payment',
        title: 'Ready for Billing & Payment',
        message: '$refNo ($staffCustLabel) passed inspection — ready for cashiering & payment.',
        requestId: (reqId as num).toInt(),
        referenceNo: refNo,
        dedupKey: 'req_${reqId}_ready_for_payment',
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Operation delay resolved! Status set to Releasable.'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    final reqId = widget.request['id'];
    final userId = widget.request['user_id'];
    final livestockType = widget.request['livestock_type'] ?? 'Livestock';

    if (_isTakeBack) {
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a pickup date'), backgroundColor: Colors.orange),
        );
        return;
      }
      setState(() => _isLoading = true);
      try {
        DateTime pickupDateTime = _selectedDate!;
        if (_selectedTime != null) {
          pickupDateTime = DateTime(
            _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
            _selectedTime!.hour, _selectedTime!.minute,
          );
        }
        final dateStr = DateFormat('MMMM d, yyyy').format(_selectedDate!);
        final timeStr = _selectedTime != null ? _selectedTime!.format(context) : '8:00 AM';

        await widget.supabase.from('requests').update({
          'anti_mortem_response': 'take_back',
          'anti_mortem_response_at': DateTime.now().toIso8601String(),
          'status': 'pickup_scheduled',
          'pickup_approved': true,
          'pickup_time': pickupDateTime.toIso8601String(),
        }).eq('id', reqId);

        final penaltyWaivedNote = _isTechnicalDelay ? ' Technical delay penalty fee has been waived.' : '';
        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: '$livestockType — Pickup Scheduled',
          message: 'Your livestock pickup has been scheduled for $dateStr at $timeStr at the Tabaco City Slaughterhouse corral.$penaltyWaivedNote Please present your reference # and valid ID upon arrival.',
          type: 'pickup_approved',
          data: {
            'request_id': reqId,
            'livestock_type': livestockType,
            'pickup_date': _selectedDate!.toIso8601String(),
            'pickup_time': timeStr,
            'admin_notes': _notesCtrl.text,
            'penalty_fee': 0.0,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pickup scheduled for $dateStr at $timeStr. Customer notified.'), backgroundColor: Colors.green.shade600),
          );
          Navigator.pop(context);
          widget.onDone();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (_isPenaltyAccepted && _isTechnicalDelay) {
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a rescheduled slaughter date'), backgroundColor: Colors.orange),
        );
        return;
      }
      setState(() => _isLoading = true);
      try {
        final dateStr = DateFormat('MMMM d, yyyy').format(_selectedDate!);
        await widget.supabase.from('requests').update({
          'anti_mortem_response': 'accept_penalty',
          'anti_mortem_response_at': DateTime.now().toIso8601String(),
          'rescheduled_date': _selectedDate!.toIso8601String().split('T')[0],
        }).eq('id', reqId);

        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: '$livestockType — Rescheduled Slaughter Confirmed',
          message: 'Your slaughter operation has been rescheduled for $dateStr following the facility technical delay. No penalty fee is charged for facility delay (₱0.00).',
          type: 'confine_confirmed',
          data: {
            'request_id': reqId,
            'livestock_type': livestockType,
            'new_date': _selectedDate!.toIso8601String(),
            'admin_notes': _notesCtrl.text,
            'penalty_fee': 0.0,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resumed slaughter date set to $dateStr. Customer notified.'), backgroundColor: Colors.green.shade600),
          );
          Navigator.pop(context);
          widget.onDone();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (_isConfine) {
      setState(() => _isLoading = true);
      try {
        await widget.supabase.from('requests').update({
          'anti_mortem_response': 'confine',
          'anti_mortem_response_at': DateTime.now().toIso8601String(),
          'status': 'confined',
        }).eq('id', reqId);

        await NotificationService.sendNotificationSafely(
          widget.supabase,
          userId: userId,
          title: '$livestockType — Confinement Under Observation',
          message: 'Your livestock has been placed into quarantine/confinement at the slaughterhouse under veterinary observation (₱0 penalty). You will be notified once cleared.',
          type: 'confine_confirmed',
          data: {
            'request_id': reqId,
            'livestock_type': livestockType,
            'admin_notes': _notesCtrl.text,
            'penalty_fee': 0.0,
          },
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Livestock placed in confinement. Customer notified.'), backgroundColor: Colors.blue.shade700),
          );
          Navigator.pop(context);
          widget.onDone();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = 'MI-${DateTime.now().year}-${widget.request['id'].toString().padLeft(3, '0')}';
    final cust = widget.request['customer_name']?.toString() ?? 'Unknown';
    final livestock = widget.request['livestock_type']?.toString() ?? '—';
    final respondedAt = widget.request['anti_mortem_response_at'];

    final headerIcon = _isTechnicalDelay
        ? (_isPenaltyAccepted ? Icons.calendar_month : Icons.undo)
        : (_isConfine ? Icons.local_hospital : Icons.undo);
    final headerColor = _isTechnicalDelay
        ? (_isPenaltyAccepted ? Colors.green.shade600 : Colors.deepOrange.shade600)
        : (_isConfine ? Colors.blue.shade600 : Colors.deepOrange.shade600);
    final headerBg = _isTechnicalDelay
        ? (_isPenaltyAccepted ? Colors.green.shade50 : Colors.deepOrange.shade50)
        : (_isConfine ? Colors.blue.shade50 : Colors.deepOrange.shade50);

    final titleText = _isTechnicalDelay
        ? (_isPenaltyAccepted
            ? 'Technical Delay: Reschedule Slaughter (₱500 Fee)'
            : 'Technical Delay: Take Livestock Back')
        : 'Mandatory 2-Day Confinement (Failed Ante-Mortem)';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: headerBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(headerIcon, color: headerColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleText,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Ref: $ref • $cust • ${_isTechnicalDelay ? "Technical Delay" : "Ante-Mortem Inspection"}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Manual Entry when customer has not responded via app
              if (!_hasCustomerAppResponse) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.phone_in_talk, size: 16, color: Colors.amber.shade900),
                          const SizedBox(width: 8),
                          Text(
                            'Walk-In / Phone Decision Entry (Customer has not responded via App)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_isTechnicalDelay)
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'accept_penalty',
                              label: Text('Reschedule (₱500 Fee)', style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.calendar_month, size: 14),
                            ),
                            ButtonSegment(
                              value: 'take_back',
                              label: Text('Take Back', style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.undo, size: 14),
                            ),
                          ],
                          selected: {_manualDecision == 'accept_penalty' || _manualDecision == 'take_back' ? _manualDecision : 'accept_penalty'},
                          onSelectionChanged: (s) => setState(() => _manualDecision = s.first),
                        )
                      else
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'confine',
                              label: Text('Confine (Observation)', style: TextStyle(fontSize: 12)),
                              icon: Icon(Icons.local_hospital, size: 14),
                            ),
                          ],
                          selected: const {'confine'},
                          onSelectionChanged: (s) => setState(() => _manualDecision = 'confine'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Customer response summary card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isTechnicalDelay
                      ? (_isPenaltyAccepted ? Colors.green.shade50 : Colors.deepOrange.shade50)
                      : (_isConfine ? Colors.blue.shade50 : Colors.deepOrange.shade50),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isTechnicalDelay
                        ? (_isPenaltyAccepted ? Colors.green.shade200 : Colors.deepOrange.shade200)
                        : (_isConfine ? Colors.blue.shade200 : Colors.deepOrange.shade200),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isTechnicalDelay
                              ? (_isPenaltyAccepted ? Icons.receipt_long : Icons.undo)
                              : (_isConfine ? Icons.local_hospital : Icons.undo),
                          size: 18,
                          color: _isTechnicalDelay
                              ? (_isPenaltyAccepted ? Colors.green.shade700 : Colors.deepOrange.shade700)
                              : (_isConfine ? Colors.blue.shade700 : Colors.deepOrange.shade700),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isTechnicalDelay
                                ? (_isPenaltyAccepted
                                    ? 'Reschedule Slaughter (₱0 Facility Delay Penalty)'
                                    : 'Take Livestock Back (₱0 Facility Delay)')
                                : 'Mandatory 2-Day Confinement (Veterinary Observation)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _isTechnicalDelay
                                  ? (_isPenaltyAccepted ? Colors.green.shade700 : Colors.deepOrange.shade700)
                                  : (_isConfine ? Colors.blue.shade700 : Colors.deepOrange.shade700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _detailRow('Livestock:', livestock),
                    _detailRow('Customer:', cust),
                    if (_isTechnicalDelay && _isPenaltyAccepted)
                      _detailRow('Terms:', 'Customer agrees to ₱500 legal finality fee to reschedule operation.')
                    else if (_isTechnicalDelay && _isTakeBack)
                      _detailRow('Terms:', 'Livestock returned to customer. Technical delay penalty is waived (₱0).')
                    else if (!_isTechnicalDelay)
                      _detailRow('Terms:', 'Livestock with health issues cannot be returned to the owner. Confined for 2 days (48 hrs) before final evaluation to proceed to slaughter or condemn.'),
                    if (respondedAt != null)
                      _detailRow('Responded:', DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(respondedAt.toString()))),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Action section
              Text(
                _isTechnicalDelay
                    ? (_isPenaltyAccepted
                        ? 'Set Rescheduled Slaughter Date'
                        : 'Schedule Livestock Pickup')
                    : (_isConfine
                        ? 'Confirm Slaughterhouse Confinement'
                        : 'Schedule Livestock Pickup'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF4A5568)),
              ),
              const SizedBox(height: 4),
              Text(
                _isTechnicalDelay
                    ? (_isPenaltyAccepted
                        ? 'Select the date when this livestock slaughter will resume. The ₱500 legal finality fee will be applied to the customer\'s bill.'
                        : 'Approve a date and time for the customer to pick up their livestock. Technical delay penalty is waived (₱0).')
                    : 'Confirm that this livestock is placed in mandatory 2-day facility confinement for veterinary observation. After 2 days, use "Evaluate Confinement" to either clear for slaughter or condemn.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),

              // Date picker (for reschedule or pickup)
              if (_isTakeBack || (_isTechnicalDelay && _isPenaltyAccepted)) ...[
                InkWell(
                  onTap: _pickDate,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18, color: Color(0xFF4A5568)),
                        const SizedBox(width: 10),
                        Text(
                          _selectedDate != null
                              ? DateFormat('MMMM d, yyyy').format(_selectedDate!)
                              : (_isTakeBack ? 'Select pickup date...' : 'Select rescheduled slaughter date...'),
                          style: TextStyle(
                            fontSize: 14,
                            color: _selectedDate != null ? Colors.black87 : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Time picker (only for take back pickup)
              if (_isTakeBack) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickTime,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 18, color: Color(0xFF4A5568)),
                        const SizedBox(width: 10),
                        Text(
                          _selectedTime != null
                              ? _selectedTime!.format(context)
                              : 'Select pickup time...',
                          style: TextStyle(
                            fontSize: 14,
                            color: _selectedTime != null ? Colors.black87 : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Text('Admin Notes (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
              const SizedBox(height: 6),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: const [SentencesCapitalizationFormatter()],
                decoration: InputDecoration(
                  hintText: 'Add any notes for the customer...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                    child: const Text('Cancel', style: TextStyle(color: Colors.black87)),
                  ),
                  if (_isTechnicalDelay && _isPenaltyAccepted)
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _markDelayResolvedAndReleasable,
                      icon: const Icon(Icons.check_circle, size: 16, color: Colors.white),
                      label: const Text('Resolve & Set Releasable', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D6A4F),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _submit,
                    icon: _isLoading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Icon(
                            _isTakeBack
                                ? Icons.schedule
                                : (_isTechnicalDelay ? Icons.calendar_month : Icons.local_hospital),
                            size: 16,
                            color: Colors.white,
                          ),
                    label: Text(
                      _isLoading
                          ? 'Saving...'
                          : _isTakeBack
                              ? 'Schedule Pickup & Notify'
                              : (_isTechnicalDelay
                                  ? 'Set Rescheduled Date & Notify'
                                  : 'Confirm Confinement & Notify'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isTakeBack
                          ? const Color(0xFFC0392B)
                          : (_isTechnicalDelay ? const Color(0xFF2563EB) : const Color(0xFF1E855A)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    ),
  );
}
