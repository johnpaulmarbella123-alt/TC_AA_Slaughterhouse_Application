import 'package:flutter/services.dart';

/// Non-web fallback: copies CSV text to clipboard so desktop/mobile testers can paste directly into Excel.
Future<bool> saveCsvBytes({
  required String filename,
  required String csvContent,
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: csvContent));
    return true;
  } catch (_) {
    return false;
  }
}
