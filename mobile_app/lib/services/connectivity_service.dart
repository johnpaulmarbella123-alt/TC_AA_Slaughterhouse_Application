import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Lightweight, zero-plugin internet reachability monitor for the Mobile App.
///
/// Uses real DNS reachability (`InternetAddress.lookup`) against the backend
/// host (with a `google.com` fallback) so captive portals or Wi-Fi without data
/// are accurately detected as offline.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isChecking = ValueNotifier<bool>(false);

  Timer? _timer;
  bool _inFlight = false;

  void startMonitoring({Duration interval = const Duration(seconds: 6)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      checkNow(silent: true);
    });
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> checkNow({bool silent = false}) async {
    if (_inFlight) return isConnected.value;
    _inFlight = true;
    if (!silent) {
      isChecking.value = true;
    }

    bool online = false;
    try {
      online = await _hasInternetReachability();
    } catch (_) {
      online = false;
    } finally {
      isConnected.value = online;
      if (!silent) {
        isChecking.value = false;
      }
      _inFlight = false;
    }
    return online;
  }

  Future<bool> _hasInternetReachability() async {
    if (kIsWeb) return true;

    const hosts = [
      'jacgcceaxblwgdxaeaqk.supabase.co',
      'google.com',
      '1.1.1.1',
    ];

    for (final host in hosts) {
      try {
        final result = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 3));
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {
        // Try next host
      }
    }
    return false;
  }
}
