import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Loads and caches bundled local TrueType fonts (Segoe UI + Consolas) from
/// `assets/fonts/`. Both font families contain the Philippine Peso glyph
/// (`\u20B1` / `₱`), ensuring zero black missing-glyph boxes and zero network
/// or CORS failures on Flutter Web and offline environments.
class PdfUnicodeFonts {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;
  final pw.Font monoRegular;
  final pw.Font monoBold;

  const PdfUnicodeFonts._({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
    required this.monoRegular,
    required this.monoBold,
  });

  static PdfUnicodeFonts? _cached;

  static Future<PdfUnicodeFonts> load() async {
    if (_cached != null) return _cached!;

    final results = await Future.wait([
      rootBundle.load('assets/fonts/segoeui.ttf'),
      rootBundle.load('assets/fonts/segoeuib.ttf'),
      rootBundle.load('assets/fonts/segoeuii.ttf'),
      rootBundle.load('assets/fonts/segoeuiz.ttf'),
      rootBundle.load('assets/fonts/consola.ttf'),
      rootBundle.load('assets/fonts/consolab.ttf'),
    ]);

    _cached = PdfUnicodeFonts._(
      regular: pw.Font.ttf(results[0]),
      bold: pw.Font.ttf(results[1]),
      italic: pw.Font.ttf(results[2]),
      boldItalic: pw.Font.ttf(results[3]),
      monoRegular: pw.Font.ttf(results[4]),
      monoBold: pw.Font.ttf(results[5]),
    );
    return _cached!;
  }

  /// Standard A4 report theme using Segoe UI (full Unicode + ₱ glyph).
  pw.ThemeData get standardTheme => pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: italic,
        boldItalic: boldItalic,
      );

  /// 80mm thermal receipt theme using Consolas monospace (full Unicode + ₱ glyph).
  pw.ThemeData get thermalTheme => pw.ThemeData.withFont(
        base: monoRegular,
        bold: monoBold,
        italic: italic,
        boldItalic: boldItalic,
      );
}
