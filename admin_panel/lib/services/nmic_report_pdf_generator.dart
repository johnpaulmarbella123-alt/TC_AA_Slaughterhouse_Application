import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'regular_dealers_service.dart';

class NmicReportPdfGenerator {
  static pw.MemoryImage? _cachedLogo;

  static Future<pw.MemoryImage?> _loadLogo() async {
    if (_cachedLogo != null) return _cachedLogo;
    try {
      final logoBytes = await rootBundle.load('assets/images/logo1.png');
      _cachedLogo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}
    return _cachedLogo;
  }

  // Helper species checkers
  static bool _isHog(String type) =>
      type.contains('hog') || type.contains('pig') || type.contains('swine') || type.contains('baboy');
  static bool _isCow(String type) =>
      type.contains('cow') || type.contains('cattle') || type.contains('baka');
  static bool _isCara(String type) =>
      type.contains('cara') || type.contains('buffalo');
  static bool _isGoat(String type) =>
      type.contains('goat') || type.contains('kambing');

  // ===========================================================================
  // 1. DAILY SLAUGHTERHOUSE PRODUCTION REPORT (Incoming Livestock & Carcass)
  // ===========================================================================
  static Future<Uint8List> generateDailyProductionReport({
    required DateTime date,
    required List<Map<String, dynamic>> requests,
  }) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final dealersService = RegularDealersService.instance;
    await dealersService.init();

    final dateStr = DateFormat('MMMM d, yyyy').format(date);
    final targetDateOnly = DateTime(date.year, date.month, date.day);

    // Filter requests for the target date
    final dailyRequests = requests.where((r) {
      final dtStr = r['scheduled_date'] ?? r['created_at'];
      if (dtStr == null) return false;
      try {
        final dt = DateTime.parse(dtStr.toString());
        return DateTime(dt.year, dt.month, dt.day) == targetDateOnly;
      } catch (_) {
        return false;
      }
    }).toList();

    // Map daily requests by customer marking and name
    final Map<String, List<Map<String, dynamic>>> reqsByMarking = {};
    for (var r in dailyRequests) {
      final marking = (r['customer_marking'] ?? r['animal_tag'] ?? r['tag_id'] ?? '').toString().trim().toUpperCase();
      final name = (r['customer_name'] ?? r['owner_name'] ?? '').toString().trim().toUpperCase();
      if (marking.isNotEmpty) {
        reqsByMarking.putIfAbsent(marking, () => []).add(r);
      }
      if (name.isNotEmpty) {
        reqsByMarking.putIfAbsent(name, () => []).add(r);
      }
    }

    final marketDealers = dealersService.marketDealers;
    final barangayDealers = dealersService.barangayDealers;

    // Helper to sum heads and weights for a dealer
    Map<String, num> getDealerStats(RegularDealer dealer) {
      final list = reqsByMarking[dealer.markings.toUpperCase().trim()] ??
          reqsByMarking[dealer.name.toUpperCase().trim()] ??
          [];
      int hogs = 0, cow = 0, cara = 0;
      double hogWt = 0, cowWt = 0, caraWt = 0;

      for (var r in list) {
        final species = (r['livestock_type'] ?? '').toString().toLowerCase();
        final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
        final wt = double.tryParse((r['carcass_weight'] ?? 0).toString()) ?? 0;

        if (_isCow(species)) {
          cow += count;
          cowWt += wt;
        } else if (_isCara(species)) {
          cara += count;
          caraWt += wt;
        } else {
          hogs += count;
          hogWt += wt;
        }
      }
      return {
        'hogs': hogs,
        'cow': cow,
        'cara': cara,
        'hogWt': hogWt,
        'cowWt': cowWt,
        'caraWt': caraWt,
      };
    }

    // Overall commodities totals
    int totHogs = 0, totCow = 0, totCara = 0, totGoat = 0;
    for (var r in dailyRequests) {
      final species = (r['livestock_type'] ?? '').toString().toLowerCase();
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      if (_isCow(species)) {
        totCow += count;
      } else if (_isCara(species)) {
        totCara += count;
      } else if (_isGoat(species)) {
        totGoat += count;
      } else {
        totHogs += count;
      }
    }

    // Page 1: Market Section (Rows 1-40)
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _buildHeader(logo, 'DAILY SLAUGHTERHOUSE PRODUCTION REPORT', '(Incoming Livestock and Carcass Production)', dateStr),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            color: PdfColors.grey300,
            child: pw.Text('MARKET SECTION', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          _buildProductionTable(marketDealers, getDealerStats),
        ],
      ),
    );

    // Page 2: Barangay Section (Rows 1-63) + Commodities box + Signatures
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            color: PdfColors.grey300,
            child: pw.Text('BARANGAY SECTION', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          _buildProductionTable(barangayDealers, getDealerStats),
          pw.SizedBox(height: 12),
          _buildCommoditiesSummaryBox(totHogs, totCow, totCara, totGoat),
          pw.SizedBox(height: 16),
          _buildSignatoriesSection(),
        ],
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // 2. MEAT DEALER LICENSING – MONTHLY LOG (31-Day Matrix)
  // ===========================================================================
  static Future<Uint8List> generateMonthlyDealerLog({
    required DateTime month,
    required List<Map<String, dynamic>> requests,
  }) async {
    final pdf = pw.Document();
    final dealersService = RegularDealersService.instance;
    await dealersService.init();

    final monthStr = DateFormat('MMMM, yyyy').format(month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final marketDealers = dealersService.marketDealers;
    final barangayDealers = dealersService.barangayDealers;

    // Filter requests for month
    final monthRequests = requests.where((r) {
      final dtStr = r['scheduled_date'] ?? r['created_at'];
      if (dtStr == null) return false;
      try {
        final dt = DateTime.parse(dtStr.toString());
        return dt.year == month.year && dt.month == month.month;
      } catch (_) {
        return false;
      }
    }).toList();

    // Map by marking and day
    final Map<String, Map<int, int>> tallyByMarking = {};
    for (var r in monthRequests) {
      final marking = (r['customer_marking'] ?? r['animal_tag'] ?? r['tag_id'] ?? '').toString().trim().toUpperCase();
      final name = (r['customer_name'] ?? r['owner_name'] ?? '').toString().trim().toUpperCase();
      final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      final dtStr = r['scheduled_date'] ?? r['created_at'];
      if (dtStr == null) continue;
      final dt = DateTime.parse(dtStr.toString());
      final day = dt.day;

      if (marking.isNotEmpty) {
        tallyByMarking.putIfAbsent(marking, () => {})[day] =
            (tallyByMarking[marking]?[day] ?? 0) + count;
      }
      if (name.isNotEmpty) {
        tallyByMarking.putIfAbsent(name, () => {})[day] =
            (tallyByMarking[name]?[day] ?? 0) + count;
      }
    }

    // Market Section Landscape
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(16),
        build: (context) => [
          _buildMonthlyHeader('MARKET SECTION', monthStr),
          pw.SizedBox(height: 6),
          _buildMonthlyGrid(marketDealers, tallyByMarking, daysInMonth),
        ],
      ),
    );

    // Barangay Section Landscape
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(16),
        build: (context) => [
          _buildMonthlyHeader('BARANGAY SECTION', monthStr),
          pw.SizedBox(height: 6),
          _buildMonthlyGrid(barangayDealers, tallyByMarking, daysInMonth),
        ],
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // 3. NMIS SLAUGHTERED ANIMALS DATA REPORT (Weekly Summary Report)
  // ===========================================================================
  static Future<Uint8List> generateNmisWeeklySummary({
    required DateTime month,
    required List<Map<String, dynamic>> requests,
  }) async {
    final pdf = pw.Document();
    final dealersService = RegularDealersService.instance;
    await dealersService.init();
    final nmic = dealersService.nmicSettings;

    final monthStr = DateFormat('MMMM yyyy').format(month);

    // Group into 5 weeks
    // Week 1: 1-7, Week 2: 8-14, Week 3: 15-21, Week 4: 22-28, Week 5: 29-31
    List<Map<String, num>> weekStats = List.generate(5, (_) => {
          'hogHeads': 0, 'hogWt': 0,
          'cattleHeads': 0, 'cattleWt': 0,
          'caraHeads': 0, 'caraWt': 0,
          'goatHeads': 0, 'goatWt': 0,
        });

    for (var r in requests) {
      final dtStr = r['scheduled_date'] ?? r['created_at'];
      if (dtStr == null) continue;
      try {
        final dt = DateTime.parse(dtStr.toString());
        if (dt.year != month.year || dt.month != month.month) continue;

        int weekIdx = (dt.day - 1) ~/ 7;
        if (weekIdx > 4) weekIdx = 4;

        final species = (r['livestock_type'] ?? '').toString().toLowerCase();
        final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
        final wt = double.tryParse((r['carcass_weight'] ?? 0).toString()) ?? 0;

        if (_isCow(species)) {
          weekStats[weekIdx]['cattleHeads'] = (weekStats[weekIdx]['cattleHeads'] ?? 0) + count;
          weekStats[weekIdx]['cattleWt'] = (weekStats[weekIdx]['cattleWt'] ?? 0) + wt;
        } else if (_isCara(species)) {
          weekStats[weekIdx]['caraHeads'] = (weekStats[weekIdx]['caraHeads'] ?? 0) + count;
          weekStats[weekIdx]['caraWt'] = (weekStats[weekIdx]['caraWt'] ?? 0) + wt;
        } else if (_isGoat(species)) {
          weekStats[weekIdx]['goatHeads'] = (weekStats[weekIdx]['goatHeads'] ?? 0) + count;
          weekStats[weekIdx]['goatWt'] = (weekStats[weekIdx]['goatWt'] ?? 0) + wt;
        } else {
          weekStats[weekIdx]['hogHeads'] = (weekStats[weekIdx]['hogHeads'] ?? 0) + count;
          weekStats[weekIdx]['hogWt'] = (weekStats[weekIdx]['hogWt'] ?? 0) + wt;
        }
      } catch (_) {}
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text('NATIONAL MEAT INSPECTION SERVICE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                  pw.Text('SLAUGHTERED ANIMALS DATA REPORT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text('Weekly Summary Report - Period: $monthStr (${nmic.establishmentName})', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _th('', flex: 1),
                    _th('HOG', flex: 2, colSpan: 2),
                    _th('CATTLE', flex: 2, colSpan: 2),
                    _th('CARABAO', flex: 2, colSpan: 2),
                    _th('GOAT', flex: 2, colSpan: 2),
                  ],
                ),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _th('WEEKS'),
                    _th('No. of Heads'),
                    _th('Dress Wt (kg)'),
                    _th('No. of Heads'),
                    _th('Dress Wt (kg)'),
                    _th('No. of Heads'),
                    _th('Dress Wt (kg)'),
                    _th('No. of Heads'),
                    _th('Dress Wt (kg)'),
                  ],
                ),
                ...List.generate(5, (i) {
                  final s = weekStats[i];
                  return pw.TableRow(
                    children: [
                      _td('Week ${i + 1}', isBold: true),
                      _td(s['hogHeads'] == 0 ? '-' : s['hogHeads'].toString()),
                      _td((s['hogWt'] ?? 0) == 0 ? '-' : NumberFormat('#,##0.0').format(s['hogWt'])),
                      _td(s['cattleHeads'] == 0 ? '-' : s['cattleHeads'].toString()),
                      _td((s['cattleWt'] ?? 0) == 0 ? '-' : NumberFormat('#,##0.0').format(s['cattleWt'])),
                      _td(s['caraHeads'] == 0 ? '-' : s['caraHeads'].toString()),
                      _td((s['caraWt'] ?? 0) == 0 ? '-' : NumberFormat('#,##0.0').format(s['caraWt'])),
                      _td(s['goatHeads'] == 0 ? '-' : s['goatHeads'].toString()),
                      _td((s['goatWt'] ?? 0) == 0 ? '-' : NumberFormat('#,##0.0').format(s['goatWt'])),
                    ],
                  );
                }),
                // Total Row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _td('TOTAL', isBold: true),
                    _td('${weekStats.fold<num>(0, (a, b) => a + (b['hogHeads'] ?? 0))}', isBold: true),
                    _td(NumberFormat('#,##0.0').format(weekStats.fold<num>(0, (a, b) => a + (b['hogWt'] ?? 0))), isBold: true),
                    _td('${weekStats.fold<num>(0, (a, b) => a + (b['cattleHeads'] ?? 0))}', isBold: true),
                    _td(NumberFormat('#,##0.0').format(weekStats.fold<num>(0, (a, b) => a + (b['cattleWt'] ?? 0))), isBold: true),
                    _td('${weekStats.fold<num>(0, (a, b) => a + (b['caraHeads'] ?? 0))}', isBold: true),
                    _td(NumberFormat('#,##0.0').format(weekStats.fold<num>(0, (a, b) => a + (b['caraWt'] ?? 0))), isBold: true),
                    _td('${weekStats.fold<num>(0, (a, b) => a + (b['goatHeads'] ?? 0))}', isBold: true),
                    _td(NumberFormat('#,##0.0').format(weekStats.fold<num>(0, (a, b) => a + (b['goatWt'] ?? 0))), isBold: true),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Text(
              'Note: Goat - ${weekStats.fold<num>(0, (a, b) => a + (b['goatHeads'] ?? 0)) == 0 ? "no slaughter recorded for the period." : "recorded as indicated."}',
              style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 8),
            ),
            pw.Spacer(),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Form No. NMIS-POSM-F-034', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Ver. No. 01', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Effectivity Date: 11 Nov 2024', style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // 4. NMIS SERVICE TRANSACTION DESCRIPTION REPORT (Form NMIS-POSM-F-034 per species)
  // ===========================================================================
  static Future<Uint8List> generateNmisServiceTransactionReport({
    required DateTime month,
    required String species, // 'HOG', 'CATTLE', 'CARABAO', 'GOAT'
    required List<Map<String, dynamic>> requests,
  }) async {
    final pdf = pw.Document();
    final dealersService = RegularDealersService.instance;
    await dealersService.init();
    final nmic = dealersService.nmicSettings;

    final monthStr = DateFormat('MMMM yyyy').format(month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final upperSpecies = species.toUpperCase();

    // Rates per species
    double amRate = 10.0;
    double pmRate = 0.25;
    if (upperSpecies == 'CATTLE' || upperSpecies == 'CARABAO') {
      amRate = 20.0;
      pmRate = 0.50;
    } else if (upperSpecies == 'GOAT') {
      amRate = 5.0;
      pmRate = 0.15;
    }

    // Daily breakdown for this species
    Map<int, Map<String, num>> dailyStats = {};
    for (int d = 1; d <= daysInMonth; d++) {
      dailyStats[d] = {'heads': 0, 'weight': 0, 'amFee': 0, 'pmFee': 0, 'total': 0};
    }

    for (var r in requests) {
      final dtStr = r['scheduled_date'] ?? r['created_at'];
      if (dtStr == null) continue;
      try {
        final dt = DateTime.parse(dtStr.toString());
        if (dt.year != month.year || dt.month != month.month) continue;

        final sp = (r['livestock_type'] ?? '').toString().toUpperCase();
        bool matches = false;
        if (upperSpecies == 'HOG' && _isHog(sp.toLowerCase())) matches = true;
        if (upperSpecies == 'CATTLE' && _isCow(sp.toLowerCase())) matches = true;
        if (upperSpecies == 'CARABAO' && _isCara(sp.toLowerCase())) matches = true;
        if (upperSpecies == 'GOAT' && _isGoat(sp.toLowerCase())) matches = true;

        if (!matches) continue;

        final day = dt.day;
        final count = int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
        final wt = double.tryParse((r['carcass_weight'] ?? 0).toString()) ?? 0;

        final am = count * amRate;
        final pm = wt * pmRate;

        dailyStats[day]!['heads'] = (dailyStats[day]!['heads'] ?? 0) + count;
        dailyStats[day]!['weight'] = (dailyStats[day]!['weight'] ?? 0) + wt;
        dailyStats[day]!['amFee'] = (dailyStats[day]!['amFee'] ?? 0) + am;
        dailyStats[day]!['pmFee'] = (dailyStats[day]!['pmFee'] ?? 0) + pm;
        dailyStats[day]!['total'] = (dailyStats[day]!['total'] ?? 0) + am + pm;
      } catch (_) {}
    }

    num totalHeads = dailyStats.values.fold(0, (a, b) => a + (b['heads'] ?? 0));
    num totalWeight = dailyStats.values.fold(0, (a, b) => a + (b['weight'] ?? 0));
    num totalAmFee = dailyStats.values.fold(0, (a, b) => a + (b['amFee'] ?? 0));
    num totalPmFee = dailyStats.values.fold(0, (a, b) => a + (b['pmFee'] ?? 0));
    num grandTotal = dailyStats.values.fold(0, (a, b) => a + (b['total'] ?? 0));

    num lguShare = grandTotal * 0.75;
    num nmisShare = grandTotal * 0.25;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Form No. NMIS-POSM-F-034', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Ver. No. 01', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Effectivity Date: 11 Nov 2024', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text('SERVICE TRANSACTION DESCRIPTION REPORT',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _metaRow('Name of Meat Establishment:', nmic.establishmentName),
                _metaRow('License To Operate No.:', nmic.ltoNumber),
                _metaRow('Address:', nmic.establishmentAddress),
                _metaRow('Period Covered (Month & Year):', monthStr),
                _metaRow('Species:', upperSpecies),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _th('Date'),
                  _th('Number of Heads'),
                  _th('Carcass Dressed Wt (Kg)'),
                  _th('Ante-Mortem Fee'),
                  _th('Post-Mortem Fee'),
                  _th('Total (AM Fee + PM Fee)'),
                ],
              ),
              ...List.generate(daysInMonth, (index) {
                final day = index + 1;
                final s = dailyStats[day]!;
                final hasData = (s['heads'] ?? 0) > 0;
                return pw.TableRow(
                  children: [
                    _td('$day', isBold: true),
                    _td(hasData ? '${s['heads']}' : ''),
                    _td(hasData ? NumberFormat('#,##0.0').format(s['weight']) : ''),
                    _td(hasData ? NumberFormat('₱#,##0.00').format(s['amFee']) : ''),
                    _td(hasData ? NumberFormat('₱#,##0.00').format(s['pmFee']) : ''),
                    _td(hasData ? NumberFormat('₱#,##0.00').format(s['total']) : ''),
                  ],
                );
              }),
              // Total Row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _td('TOTAL', isBold: true),
                  _td('$totalHeads', isBold: true),
                  _td(NumberFormat('#,##0.0').format(totalWeight), isBold: true),
                  _td(NumberFormat('₱#,##0.00').format(totalAmFee), isBold: true),
                  _td(NumberFormat('₱#,##0.00').format(totalPmFee), isBold: true),
                  _td(NumberFormat('₱#,##0.00').format(grandTotal), isBold: true),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            color: PdfColors.grey100,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Breakdown:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text('LGU Share (75%) = ${NumberFormat("₱#,##0.00").format(lguShare)}', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('NMIS Share (25%) = ${NumberFormat("₱#,##0.00").format(nmisShare)}', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _sigBox('Prepared by:', nmic.dmioOfficerName, nmic.dmioOfficerTitle),
              _sigBox('Verified by:', nmic.nmicOfficerName, nmic.nmicOfficerTitle),
              _sigBox('CONFORME:', nmic.plantRepresentative, nmic.plantRepTitle),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text('Note: Official basis of Ante- and Post-Mortem Inspection fees:',
              style: pw.TextStyle(fontSize: 7.5, fontStyle: pw.FontStyle.italic)),
          pw.Text(
              '(  ) DA AO No. 13, S. 1993: AM Fee = ₱$amRate/hd, PM Fee = ₱$pmRate/Kg\n'
              '(X) ${nmic.feeBasisDetails}',
              style: const pw.TextStyle(fontSize: 7)),
        ],
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // 5. INDIVIDUAL CUSTOMER SLAUGHTER RECORDS (Audit Trail)
  // ===========================================================================
  static Future<Uint8List> generateCustomerSlaughterHistoryReport({
    required String customerName,
    required String marking,
    required String periodLabel,
    required List<Map<String, dynamic>> requests,
  }) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();

    int totalHeads = 0;
    double totalWeight = 0;
    
    for (var r in requests) {
      totalHeads += int.tryParse((r['animal_count'] ?? 1).toString()) ?? 1;
      totalWeight += double.tryParse((r['carcass_weight'] ?? 0).toString()) ?? 0;
                }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _buildHeader(logo, 'CUSTOMER SLAUGHTERHOUSE OFFICIAL PRODUCTION RECORD', 'NMIC Audit & Verification Certificate', periodLabel),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border.all(color: PdfColors.grey300)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Customer / Meat Dealer: $customerName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('Assigned Marking Tag: $marking (Permanently Locked)', style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue900)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Period: $periodLabel', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Total Heads: $totalHeads | Weight: ${NumberFormat("#,##0.0").format(totalWeight)} kg',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _th('Date'),
                  _th('Ref #'),
                  _th('Species'),
                  _th('Heads'),
                  _th('Carcass Wt (kg)'),
                  _th('Inspection Result'),
                  _th('Fee Paid'),
                ],
              ),
              ...requests.map((r) {
                final dt = r['scheduled_date'] ?? r['created_at'] ?? '';
                final ref = r['reference_no'] ?? r['id'] ?? '-';
                final species = r['livestock_type'] ?? 'Hog';
                final heads = r['animal_count'] ?? 1;
                final wt = r['carcass_weight'] ?? 0;
                final res = r['status'] ?? 'Passed';
                final fee = r['total_fee'] ?? r['total_amount'] ?? 0;
                return pw.TableRow(
                  children: [
                    _td(dt.toString().split('T').first),
                    _td(ref.toString()),
                    _td(species.toString()),
                    _td('$heads'),
                    _td(NumberFormat('#,##0.0').format(double.tryParse('$wt') ?? 0)),
                    _td(res.toString()),
                    _td(NumberFormat('₱#,##0.00').format(double.tryParse('$fee') ?? 0)),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _sigBox('Recorded by:', 'FERNANDO BALINGBING', 'Livestock Recorder'),
              _sigBox('Inspected by:', 'MELCHOR VARGAS', 'Meat Inspector'),
              _sigBox('Certified Correct:', 'JOSE ERNESTO ROS', 'Slaughterhouse Designate'),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // 6. OFFICIAL TRANSMITTAL LETTER TO NMIC
  // ===========================================================================
  static Future<Uint8List> generateTransmittalLetter({
    required String periodLabel,
    required String reportTitle,
    required NmicSettings nmic,
    String? customBody,
  }) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();

    final dateStr = DateFormat('MMMM d, yyyy').format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildOfficialLetterhead(logo),
            pw.SizedBox(height: 20),
            pw.Text(dateStr, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 14),
            pw.Text(nmic.nmicOfficerName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(nmic.nmicOfficerTitle, style: const pw.TextStyle(fontSize: 9)),
            pw.Text('National Meat Inspection Service (NMIS) Regional Office', style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Regional Field Office No. 5', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 16),
            pw.Text('SUBJECT: TRANSMITTAL OF SLAUGHTERHOUSE PRODUCTION & INSPECTION REPORT ($periodLabel)',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.SizedBox(height: 12),
            pw.Text('Dear ${nmic.nmicOfficerName},', style: const pw.TextStyle(fontSize: 9.5)),
            pw.SizedBox(height: 8),
            pw.Text(
              customBody ??
                  'Warm greetings from the City Government of Tabaco.\n\n'
                  'Pursuant to Republic Act No. 9296 (Meat Inspection Code of the Philippines) as amended by RA 10536 and '
                  'relevant NMIS regulations, we are officially transmitting herewith the soft copy of the '
                  '$reportTitle covering the period of $periodLabel.\n\n'
                  'This submission includes detailed incoming livestock, carcass production weight, ante- and post-mortem '
                  'inspection summaries, customer-level slaughter counts, and the corresponding LGU-NMIS fee sharing '
                  'schedules under ${nmic.feeBasisDetails}.\n\n'
                  'Certified hard copies and original official receipts are preserved at the Abattoir Office and will be '
                  'readily presented to your Meat Inspection Officers during the scheduled weekly on-site inspection.',
              style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 1.5),
            ),
            pw.SizedBox(height: 14),
            pw.Text('Thank you for your continued guidance and regulatory support.', style: const pw.TextStyle(fontSize: 9.5)),
            pw.SizedBox(height: 24),
            pw.Text('Very truly yours,', style: const pw.TextStyle(fontSize: 9.5)),
            pw.SizedBox(height: 30),
            pw.Text(nmic.plantRepresentative, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text(nmic.plantRepTitle, style: const pw.TextStyle(fontSize: 9)),
            pw.Text(nmic.establishmentName, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.Text('Cc: City Abattoir Office, POSMS Albay, NMIS Regional Director',
                style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  // ===========================================================================
  // WIDGET HELPERS
  // ===========================================================================
  static pw.Widget _buildOfficialLetterhead(pw.MemoryImage? logo) {
    return pw.Row(
      children: [
        if (logo != null) pw.Image(logo, width: 48, height: 48),
        pw.SizedBox(width: 14),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Republic of the Philippines', style: const pw.TextStyle(fontSize: 8)),
            pw.Text('Province of Albay', style: const pw.TextStyle(fontSize: 8)),
            pw.Text('CITY OF TABACO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.Text('OFFICE OF THE CITY VETERINARIAN / CITY ABATTOIR',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.green900)),
            pw.Text('San Roque, Tabaco City, Albay', style: const pw.TextStyle(fontSize: 7.5)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildHeader(pw.MemoryImage? logo, String title, String subtitle, String dateStr) {
    return pw.Column(
      children: [
        pw.Center(child: pw.Text('Republic of the Philippines', style: const pw.TextStyle(fontSize: 8))),
        pw.Center(child: pw.Text('Province of Albay', style: const pw.TextStyle(fontSize: 8))),
        pw.Center(child: pw.Text('City of Tabaco', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
        pw.SizedBox(height: 3),
        pw.Center(child: pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11))),
        pw.Center(child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9))),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Date: $dateStr', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Text('Plant LTO: LTO-SL-05-004', style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildProductionTable(
    List<RegularDealer> dealers,
    Map<String, num> Function(RegularDealer) getStats,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FlexColumnWidth(3.0),
        2: const pw.FlexColumnWidth(1.4),
        3: const pw.FixedColumnWidth(26),
        4: const pw.FixedColumnWidth(26),
        5: const pw.FixedColumnWidth(26),
        6: const pw.FixedColumnWidth(36),
        7: const pw.FixedColumnWidth(36),
        8: const pw.FixedColumnWidth(36),
        9: const pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _th('No.'),
            _th('Name of Owner'),
            _th('Markings'),
            _th('Hogs', fontSize: 6.5),
            _th('Cow', fontSize: 6.5),
            _th('Cara', fontSize: 6.5),
            _th('Hogs (kg)', fontSize: 6),
            _th('Cow (kg)', fontSize: 6),
            _th('Cara (kg)', fontSize: 6),
            _th('Remarks', fontSize: 6.5),
          ],
        ),
        ...dealers.map((d) {
          final stats = getStats(d);
          final hasHogs = (stats['hogs'] ?? 0) > 0;
          final hasCow = (stats['cow'] ?? 0) > 0;
          final hasCara = (stats['cara'] ?? 0) > 0;
          return pw.TableRow(
            children: [
              _td('${d.dealerNumber}', fontSize: 7),
              _td(d.name, fontSize: 7, align: pw.TextAlign.left),
              _td(d.markings, fontSize: 7, isBold: true),
              _td(hasHogs ? '${stats['hogs']}' : '', fontSize: 7),
              _td(hasCow ? '${stats['cow']}' : '', fontSize: 7),
              _td(hasCara ? '${stats['cara']}' : '', fontSize: 7),
              _td(hasHogs ? NumberFormat('#,##0.0').format(stats['hogWt']) : '', fontSize: 6.5),
              _td(hasCow ? NumberFormat('#,##0.0').format(stats['cowWt']) : '', fontSize: 6.5),
              _td(hasCara ? NumberFormat('#,##0.0').format(stats['caraWt']) : '', fontSize: 6.5),
              _td('', fontSize: 6.5),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildCommoditiesSummaryBox(int hogs, int cow, int cara, int goat) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('ANIMAL COMMODITIES SLAUGHTERED', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _th('HOGS'),
                _th('COW'),
                _th('CARABAO'),
                _th('GOAT'),
                _th('REMARKS'),
              ],
            ),
            pw.TableRow(
              children: [
                _td('$hogs', isBold: true, fontSize: 9),
                _td('$cow', isBold: true, fontSize: 9),
                _td('$cara', isBold: true, fontSize: 9),
                _td('$goat', isBold: true, fontSize: 9),
                _td(goat == 0 ? 'No goat slaughtered' : 'Operational', fontSize: 8),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSignatoriesSection() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('LIVESTOCK RECORDERS ON DUTY:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _sigPlain('FERNANDO BALINGBING', 'Livestock Recorder'),
            _sigPlain('ERWIN BIEN', 'Livestock Recorder'),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text('MEAT INSPECTORS ON DUTY:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _sigPlain('MELCHOR VARGAS', 'Meat Inspector'),
            _sigPlain('RODEL B. BALINGBING', 'Meat Inspector'),
            _sigPlain('HENRY GASCON', 'Meat Inspector'),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text('CERTIFIED AND VALIDATED BY:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _sigPlain('JOSE ERNESTO ROS', 'Slaughterhouse Designate'),
            _sigPlain('JONEL P. ARCOS', 'Slaughterhouse Master 1'),
            _sigPlain('KIM RONAN ROMERO, DVM', 'OIC-City Veterinarian'),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildMonthlyHeader(String section, String monthStr) {
    return pw.Column(
      children: [
        pw.Center(child: pw.Text('Republic of the Philippines - Province of Albay - City of Tabaco', style: const pw.TextStyle(fontSize: 8))),
        pw.Center(child: pw.Text('CITY ABATTOIR OFFICE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
        pw.Center(child: pw.Text('DAILY SLAUGHTERHOUSE PRODUCTION REPORT - Meat Dealer Licensing - Monthly Log', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
        pw.Center(child: pw.Text('Month: $monthStr | $section', style: const pw.TextStyle(fontSize: 8.5))),
      ],
    );
  }

  static pw.Widget _buildMonthlyGrid(
    List<RegularDealer> dealers,
    Map<String, Map<int, int>> tallyByMarking,
    int daysInMonth,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _th('No.', fontSize: 6),
            _th('Name of Owner', fontSize: 6),
            _th('Mark', fontSize: 6),
            ...List.generate(daysInMonth, (i) => _th('${i + 1}', fontSize: 5)),
            _th('TOTAL', fontSize: 6),
          ],
        ),
        ...dealers.map((d) {
          final tMap = tallyByMarking[d.markings.toUpperCase().trim()] ??
              tallyByMarking[d.name.toUpperCase().trim()] ??
              {};
          int rowTotal = 0;
          return pw.TableRow(
            children: [
              _td('${d.dealerNumber}', fontSize: 6),
              _td(d.name, fontSize: 6, align: pw.TextAlign.left),
              _td(d.markings, fontSize: 6, isBold: true),
              ...List.generate(daysInMonth, (i) {
                final dayVal = tMap[i + 1] ?? 0;
                rowTotal += dayVal;
                return _td(dayVal > 0 ? '$dayVal' : '', fontSize: 5);
              }),
              _td(rowTotal > 0 ? '$rowTotal' : '', fontSize: 6, isBold: true),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _th(String text, {double fontSize = 7.5, int flex = 1, int? colSpan}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2.5),
      child: pw.Center(
        child: pw.Text(text,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: fontSize)),
      ),
    );
  }

  // ===========================================================================
  // 5. MEAT DEALERS DIRECTORY & REGISTRATION ROSTER PDF
  // ===========================================================================
  static Future<Uint8List> generateDealersDirectoryPdf({
    required List<RegularDealer> dealers,
    required Map<String, int> dealerHeadsCount,
  }) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final dealersService = RegularDealersService.instance;
    await dealersService.init();
    final nmic = dealersService.nmicSettings;
    final generatedDate = DateFormat('MMMM d, yyyy').format(DateTime.now());

    final marketCount = dealers.where((d) => d.category == 'market').length;
    final brgyCount = dealers.where((d) => d.category == 'barangay').length;
    final newCount = dealers.where((d) => d.isNew).length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context ctx) {
          return pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null) pw.Image(logo, width: 44, height: 44),
                  if (logo != null) pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('REPUBLIC OF THE PHILIPPINES', style: const pw.TextStyle(fontSize: 8.5)),
                        pw.Text('CITY GOVERNMENT OF TABACO • CITY VETERINARY OFFICE', style: const pw.TextStyle(fontSize: 8.5)),
                        pw.Text('TABACO CITY SLAUGHTERHOUSE (ABATTOIR)', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                        pw.Text('MEAT DEALERS DIRECTORY & OFFICIAL REGISTRATION ROSTER', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('LTO: ${nmic.ltoNumber}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Date: $generatedDate', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('NMIS Region V Compliance', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1, color: PdfColors.green800),
              pw.SizedBox(height: 6),
            ],
          );
        },
        footer: (pw.Context ctx) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Official Meat Dealer Roster • Tabaco City Abattoir Management System', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
              pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
            ],
          );
        },
        build: (pw.Context ctx) {
          return [
            // KPI Summary Row
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Text('Total Registered Dealers: ${dealers.length}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Market Dealers: $marketCount', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.blue800)),
                  pw.Text('Barangay Dealers: $brgyCount', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.amber800)),
                  pw.Text('New Dealers (30d): $newCount', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // Table of Dealers
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(30),
                1: pw.FlexColumnWidth(3.2),
                2: pw.FixedColumnWidth(65),
                3: pw.FixedColumnWidth(70),
                4: pw.FixedColumnWidth(75),
                5: pw.FixedColumnWidth(55),
                6: pw.FixedColumnWidth(65),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.green50),
                  children: [
                    _th('#'),
                    _th('Meat Dealer Full Name'),
                    _th('Marking'),
                    _th('Category'),
                    _th('Contact'),
                    _th('Heads'),
                    _th('Status'),
                  ],
                ),
                ...dealers.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final d = entry.value;
                  final cleanName = d.name.trim().toLowerCase();
                  final heads = dealerHeadsCount[cleanName] ?? 0;
                  final isEven = idx % 2 == 0;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: isEven ? PdfColors.grey50 : PdfColors.white),
                    children: [
                      _td(idx.toString(), fontSize: 7.5),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                        child: pw.Text(
                          d.name,
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                        child: pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 1, horizontal: 3),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.green800, width: 0.5),
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                          ),
                          child: pw.Text(
                            d.markings,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                          ),
                        ),
                      ),
                      _td(d.category.toUpperCase(), fontSize: 7.5),
                      _td(d.phone != null && d.phone!.isNotEmpty ? d.phone! : '—', fontSize: 7),
                      _td(heads > 0 ? '$heads' : '0', fontSize: 7.5, isBold: heads > 0),
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                        child: pw.Text(
                          d.isNew ? 'NEW DEALER' : (d.isActive ? 'Active' : 'Inactive'),
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                            color: d.isNew ? PdfColors.green800 : (d.isActive ? PdfColors.grey800 : PdfColors.red800),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 20),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _sigBox('Prepared / Certified by:', nmic.plantRepresentative, nmic.plantRepTitle),
                _sigBox('Attested & Inspected by:', nmic.dmioOfficerName, nmic.dmioOfficerTitle),
                _sigBox('Noted by (POSMS Head):', nmic.nmicOfficerName, nmic.nmicOfficerTitle),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _td(String text, {double fontSize = 7.5, bool isBold = false, pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(fontSize: fontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }

  static pw.Widget _metaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 170, child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
          pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 8.5))),
        ],
      ),
    );
  }

  static pw.Widget _sigBox(String role, String name, String title) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(role, style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 18),
        pw.Text(name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, decoration: pw.TextDecoration.underline)),
        pw.Text(title, style: const pw.TextStyle(fontSize: 7.5)),
      ],
    );
  }

  static pw.Widget _sigPlain(String name, String title) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 14),
        pw.Text(name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5, decoration: pw.TextDecoration.underline)),
        pw.Text(title, style: const pw.TextStyle(fontSize: 6.5)),
      ],
    );
  }
}
