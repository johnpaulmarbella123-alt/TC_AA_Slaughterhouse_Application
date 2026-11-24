import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents one animal head inside a slaughter request's `animals_in_lot` JSONB list.
class AnimalLotItem {
  int headNo;
  String earTag;
  String color;
  String origin;
  String sex; // '', 'Male', 'Female'
  double? liveWeight;

  AnimalLotItem({
    required this.headNo,
    this.earTag = '',
    this.color = '',
    this.origin = '',
    this.sex = '',
    this.liveWeight,
  });

  factory AnimalLotItem.fromJson(Map<String, dynamic> json, int fallbackIndex) {
    final wtRaw = json['live_weight'];
    double? wt;
    if (wtRaw is num) {
      wt = wtRaw.toDouble();
    } else if (wtRaw != null && wtRaw.toString().trim().isNotEmpty) {
      wt = double.tryParse(wtRaw.toString().trim());
    }
    return AnimalLotItem(
      headNo: (json['head_no'] as num?)?.toInt() ?? fallbackIndex,
      earTag: (json['ear_tag'] ?? '').toString().trim(),
      color: (json['color'] ?? '').toString().trim(),
      origin: (json['origin'] ?? '').toString().trim(),
      sex: (json['sex'] ?? '').toString().trim(),
      liveWeight: (wt != null && wt > 0) ? wt : null,
    );
  }

  Map<String, dynamic> toJson(int index) {
    return {
      'head_no': index + 1,
      'ear_tag': earTag.trim().isNotEmpty ? earTag.trim() : 'Auto #${index + 1}',
      'color': color.trim(),
      'origin': origin.trim(),
      'sex': sex.trim(),
      'live_weight': liveWeight ?? 0.0,
    };
  }

  /// Parses `animals_in_lot` from a request row, gracefully generating placeholder rows
  /// for legacy requests that only have `animal_count`.
  static List<AnimalLotItem> parseList(
    dynamic raw, {
    int fallbackCount = 1,
    String fallbackOrigin = 'Tabaco City',
  }) {
    List<dynamic> decoded = [];
    if (raw is List) {
      decoded = raw;
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is List) decoded = d;
      } catch (_) {}
    }

    if (decoded.isNotEmpty) {
      final list = <AnimalLotItem>[];
      for (int i = 0; i < decoded.length; i++) {
        final item = decoded[i];
        if (item is Map) {
          list.add(AnimalLotItem.fromJson(Map<String, dynamic>.from(item), i + 1));
        }
      }
      if (list.isNotEmpty) return list;
    }

    final count = fallbackCount > 0 ? fallbackCount : 1;
    return List.generate(
      count,
      (i) => AnimalLotItem(
        headNo: i + 1,
        earTag: '',
        color: '',
        origin: fallbackOrigin,
        sex: '',
        liveWeight: null,
      ),
    );
  }
}

/// Interactive Admin/Clerk per-head editor matching the "Animals in Lot (+ Add Head)" layout,
/// including Ear-Tag # assignment.
class AnimalsInLotEditor extends StatefulWidget {
  final List<AnimalLotItem> items;
  final String defaultOrigin;
  final ValueChanged<List<AnimalLotItem>> onChanged;
  final bool tagOnlyMode;

  const AnimalsInLotEditor({
    super.key,
    required this.items,
    required this.defaultOrigin,
    required this.onChanged,
    this.tagOnlyMode = false,
  });

  @override
  State<AnimalsInLotEditor> createState() => _AnimalsInLotEditorState();
}

class _AnimalsInLotEditorState extends State<AnimalsInLotEditor> {
  Widget _buildReadOnlyDetail(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Color(0xFF475569),
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value.isNotEmpty ? value : '—',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  void _addHead() {
    final next = List<AnimalLotItem>.from(widget.items)
      ..add(
        AnimalLotItem(
          headNo: widget.items.length + 1,
          earTag: '',
          color: '',
          origin: widget.defaultOrigin,
          sex: '',
          liveWeight: null,
        ),
      );
    widget.onChanged(next);
  }

  void _removeHead(int index) {
    if (widget.items.length <= 1) return;
    final next = List<AnimalLotItem>.from(widget.items)..removeAt(index);
    for (int i = 0; i < next.length; i++) {
      next[i].headNo = i + 1;
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Animals in Lot ($count ${count == 1 ? 'head' : 'heads'})',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A202C),
              ),
            ),
            if (!widget.tagOnlyMode)
              OutlinedButton.icon(
                onPressed: _addHead,
                icon: const Icon(Icons.add, size: 16, color: Color(0xFF1A202C)),
                label: const Text(
                  'Add Head',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1A202C)),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9),
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(widget.items.length, (i) {
          final item = widget.items[i];
          if (widget.tagOnlyMode) {
            final wtLabel = (item.liveWeight != null && item.liveWeight! > 0)
                ? '${item.liveWeight!.toStringAsFixed(1)} kg'
                : '—';
            return Container(
              key: ValueKey('admin_tag_only_${i}_${widget.items.length}'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Head #${i + 1}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: item.earTag,
                          onChanged: (v) => item.earTag = v,
                          decoration: InputDecoration(
                            labelText: 'Ear-Tag #',
                            hintText: 'Auto #${i + 1}',
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF0F5132), width: 1.8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildReadOnlyDetail('Color', item.color),
                      _buildReadOnlyDetail('Origin', item.origin),
                      _buildReadOnlyDetail('Sex', item.sex),
                      _buildReadOnlyDetail('Live Wt', wtLabel),
                    ],
                  ),
                ],
              ),
            );
          }
          return Container(
            key: ValueKey('admin_lot_${i}_${widget.items.length}'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFBFD),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: item.earTag,
                        onChanged: (v) => item.earTag = v,
                        decoration: InputDecoration(
                          labelText: 'Ear-Tag #',
                          hintText: 'Auto #${i + 1}',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        initialValue: item.color,
                        onChanged: (v) => item.color = v,
                        decoration: InputDecoration(
                          labelText: 'Color',
                          hintText: 'e.g. White',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: item.origin,
                        onChanged: (v) => item.origin = v,
                        decoration: InputDecoration(
                          labelText: 'Origin (Brgy/Mun)',
                          hintText: 'Tabaco City',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: const ['', 'Male', 'Female'].contains(item.sex) ? item.sex : '',
                        decoration: InputDecoration(
                          labelText: 'Sex (opt.)',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('—')),
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(value: 'Female', child: Text('Female')),
                        ],
                        onChanged: (v) {
                          setState(() => item.sex = v ?? '');
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: (item.liveWeight != null && item.liveWeight! > 0)
                            ? item.liveWeight!.toStringAsFixed(1)
                            : '',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        onChanged: (v) => item.liveWeight = double.tryParse(v.trim()),
                        decoration: InputDecoration(
                          labelText: 'Live Wt (kg, opt.)',
                          hintText: '0.0',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: widget.items.length > 1 ? () => _removeHead(i) : null,
                      tooltip: widget.items.length > 1 ? 'Remove head' : 'At least 1 head required',
                      icon: Icon(
                        Icons.delete_outline,
                        color: widget.items.length > 1 ? const Color(0xFFDC2626) : Colors.grey.shade400,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: widget.items.length > 1
                            ? const Color(0xFFFEF2F2)
                            : Colors.grey.shade100,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Read-only per-head summary table used in Receiving details and Slaughter & Inspection.
class AnimalsInLotReadOnlyList extends StatelessWidget {
  final dynamic rawAnimalsInLot;
  final int fallbackCount;
  final String fallbackOrigin;

  const AnimalsInLotReadOnlyList({
    super.key,
    required this.rawAnimalsInLot,
    this.fallbackCount = 1,
    this.fallbackOrigin = 'Tabaco City',
  });

  @override
  Widget build(BuildContext context) {
    final list = AnimalLotItem.parseList(
      rawAnimalsInLot,
      fallbackCount: fallbackCount,
      fallbackOrigin: fallbackOrigin,
    );

    final hasDetailedData = rawAnimalsInLot is List && rawAnimalsInLot.isNotEmpty;
    if (!hasDetailedData) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Animals in Lot (${list.length} ${list.length == 1 ? 'head' : 'heads'})',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: const TableBorder(
                  horizontalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                ),
                columnWidths: const {
                  0: FixedColumnWidth(32),
                  1: FlexColumnWidth(1.3),
                  2: FlexColumnWidth(1.1),
                  3: FlexColumnWidth(1.8),
                  4: FlexColumnWidth(0.9),
                  5: FlexColumnWidth(1.2),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
                    children: [
                      _LotHeaderCell('#'),
                      _LotHeaderCell('Ear-Tag #'),
                      _LotHeaderCell('Color'),
                      _LotHeaderCell('Origin'),
                      _LotHeaderCell('Sex'),
                      _LotHeaderCell('Live Wt'),
                    ],
                  ),
                  ...List.generate(list.length, (i) {
                    final item = list[i];
                    final tag = item.earTag.isNotEmpty ? item.earTag : 'Pending';
                    return TableRow(
                      decoration: const BoxDecoration(color: Colors.white),
                      children: [
                        _LotDataCell('${i + 1}'),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: item.earTag.isNotEmpty
                                    ? const Color(0xFFD1FAE5)
                                    : const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tag,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: item.earTag.isNotEmpty
                                      ? const Color(0xFF047857)
                                      : const Color(0xFFB45309),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _LotDataCell(item.color.isNotEmpty ? item.color : '—'),
                        _LotDataCell(item.origin.isNotEmpty ? item.origin : '—'),
                        _LotDataCell(item.sex.isNotEmpty ? item.sex : '—'),
                        _LotDataCell(
                          (item.liveWeight != null && item.liveWeight! > 0)
                              ? '${item.liveWeight!.toStringAsFixed(1)} kg'
                              : '—',
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LotHeaderCell extends StatelessWidget {
  final String text;
  const _LotHeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF475569),
        ),
      ),
    );
  }
}

class _LotDataCell extends StatelessWidget {
  final String text;
  const _LotDataCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }
}
