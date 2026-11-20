import 'csv_export_helper_stub.dart'
    if (dart.library.js_interop) 'csv_export_helper_web.dart' as impl;

/// Escapes a single CSV field per RFC 4180.
String _escapeCsvField(dynamic value) {
  final str = (value ?? '').toString();
  if (str.contains(',') || str.contains('"') || str.contains('\n') || str.contains('\r')) {
    return '"${str.replaceAll('"', '""')}"';
  }
  return str;
}

/// Builds a UTF-8 BOM Excel-compatible CSV string from headers and rows.
String buildCsvContent(List<String> headers, List<List<dynamic>> rows) {
  final buffer = StringBuffer('\uFEFF');
  buffer.writeln(headers.map(_escapeCsvField).join(','));
  for (final row in rows) {
    buffer.writeln(row.map(_escapeCsvField).join(','));
  }
  return buffer.toString();
}

/// Triggers a CSV file download (Web) or clipboard/share fallback (Non-Web).
Future<bool> downloadCsvFile({
  required String filename,
  required List<String> headers,
  required List<List<dynamic>> rows,
}) {
  final content = buildCsvContent(headers, rows);
  final safeName = filename.toLowerCase().endsWith('.csv') ? filename : '$filename.csv';
  return impl.saveCsvBytes(filename: safeName, csvContent: content);
}
