import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_settings_service.dart';

/// Centralized, auto-reconnecting Supabase Realtime hub for the Admin Panel.
///
/// Maintains ONE multiplexed WebSocket channel listening to all core transaction
/// tables (`requests`, `payments`, `slaughter_inspection`, `regular_dealers`,
/// `reports`, `staff_notifications`) and broadcasts debounced table-change
/// events to every mounted Admin, Clerk, and Inspector screen.
class AdminRealtimeHub {
  AdminRealtimeHub._internal();
  static final AdminRealtimeHub instance = AdminRealtimeHub._internal();

  static const List<String> watchedTables = [
    'requests',
    'payments',
    'slaughter_inspection',
    'regular_dealers',
    'reports',
    'staff_notifications',
    'walkin_sms_replies',
  ];

  final StreamController<String> _controller = StreamController<String>.broadcast();
  final Map<String, Timer> _debounceTimers = {};

  RealtimeChannel? _channel;
  Timer? _reconnectTimer;
  bool _started = false;
  int _reconnectAttempt = 0;

  /// Broadcast stream emitting the name of the Postgres table that changed
  /// (e.g., `'requests'`, `'payments'`, `'slaughter_inspection'`,
  /// `'regular_dealers'`, `'reports'`, `'staff_notifications'`).
  Stream<String> get stream => _controller.stream;

  /// Convenience helper to subscribe to a specific subset of tables.
  StreamSubscription<String> listen(
    Set<String> tables,
    VoidCallback onEvent,
  ) {
    return _controller.stream.listen((table) {
      if (tables.contains(table)) {
        onEvent();
      }
    });
  }

  /// Starts the shared Realtime subscription (idempotent).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _reconnectAttempt = 0;
    try {
      await AppSettingsService.instance.ensureAdminAuthSession();
    } catch (e) {
      debugPrint('AdminRealtimeHub auth notice: $e');
    }
    if (!_started) return;
    _openChannel();
  }

  /// Stops the shared Realtime subscription and cleans up timers.
  void stop() {
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
    _closeChannel();
  }

  void _openChannel() {
    _closeChannel();
    if (!_started) return;

    try {
      final supabase = Supabase.instance.client;
      final channel = supabase.channel('public:admin_realtime_hub');

      for (final table in watchedTables) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (payload) {
            _emitDebounced(table);
          },
        );
      }

      _channel = channel;

      channel.subscribe((status, [error]) {
        // Ignore callbacks from stale/replaced channels (e.g. closed during reconnect)
        if (!identical(_channel, channel)) return;

        if (status == RealtimeSubscribeStatus.subscribed) {
          _reconnectAttempt = 0;
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          debugPrint('AdminRealtimeHub: subscribed to ${watchedTables.join(', ')}');
        } else if (status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.closed) {
          debugPrint('AdminRealtimeHub status=$status error=$error');
          if (_started) {
            _scheduleReconnect();
          }
        }
      });
    } catch (e) {
      debugPrint('AdminRealtimeHub subscribe error: $e');
      if (_started) {
        _scheduleReconnect();
      }
    }
  }

  void _closeChannel() {
    final existing = _channel;
    _channel = null;
    if (existing != null) {
      try {
        Supabase.instance.client.removeChannel(existing);
      } catch (_) {}
    }
  }

  void _scheduleReconnect() {
    if (!_started) return;
    if (_reconnectTimer?.isActive ?? false) return;
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 6);
    final delaySeconds = (_reconnectAttempt * 2).clamp(2, 15);
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (!_started) return;
      try {
        await AppSettingsService.instance.ensureAdminAuthSession();
      } catch (_) {}
      if (_started) {
        _openChannel();
      }
    });
  }

  void _emitDebounced(String table) {
    _debounceTimers[table]?.cancel();
    _debounceTimers[table] = Timer(const Duration(milliseconds: 250), () {
      _debounceTimers.remove(table);
      if (!_controller.isClosed) {
        _controller.add(table);
      }
    });
  }
}
