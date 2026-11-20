import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

Future<bool> saveCsvBytes({
  required String filename,
  required String csvContent,
}) async {
  try {
    final bytes = Uint8List.fromList(utf8.encode(csvContent));
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'text/csv;charset=utf-8;'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}
