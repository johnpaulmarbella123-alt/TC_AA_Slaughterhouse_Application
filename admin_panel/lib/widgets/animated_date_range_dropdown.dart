import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Compact, smooth animated date-range dropdown anchored directly beneath its trigger pill.
/// Replaces Flutter's full-screen `showDateRangePicker` route with a fluid brand-green panel.
class AnimatedDateRangeDropdown extends StatefulWidget {
  final DateTimeRange selectedRange;
  final String label;
  final ValueChanged<DateTimeRange> onRangeSelected;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final int autoOpenVersion;

  const AnimatedDateRangeDropdown({
    super.key,
    required this.selectedRange,
    required this.label,
    required this.onRangeSelected,
    this.firstDate,
    this.lastDate,
    this.autoOpenVersion = 0,
  });

  @override
  State<AnimatedDateRangeDropdown> createState() => _AnimatedDateRangeDropdownState();
}

class _AnimatedDateRangeDropdownState extends State<AnimatedDateRangeDropdown>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<Offset> _slideAnim;
  bool _isOpen = false;

  late DateTime _visibleMonth;
  DateTime? _draftStart;
  DateTime? _draftEnd;

  @override
  void initState() {
    super.initState();
    _syncDraftFromWidget();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 150),
    );
    final curved = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fadeAnim = curved;
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(curved);
    _slideAnim = Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).animate(curved);

    if (widget.autoOpenVersion > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isOpen) _openDropdown();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedDateRangeDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedRange != widget.selectedRange && !_isOpen) {
      _syncDraftFromWidget();
    }
    if (widget.autoOpenVersion != oldWidget.autoOpenVersion && widget.autoOpenVersion > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isOpen) _openDropdown();
      });
    }
  }

  void _syncDraftFromWidget() {
    _draftStart = _dateOnly(widget.selectedRange.start);
    _draftEnd = _dateOnly(widget.selectedRange.end);
    _visibleMonth = DateTime(_draftEnd!.year, _draftEnd!.month);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void dispose() {
    _closeDropdown(immediate: true);
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    if (_isOpen) return;
    _syncDraftFromWidget();

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final triggerSize = renderBox.size;
    final triggerOffset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(context).size.width;
    const double menuWidth = 324.0;

    double dx = (triggerSize.width - menuWidth) / 2;
    final projectedLeft = triggerOffset.dx + dx;
    if (projectedLeft < 12) {
      dx = 12 - triggerOffset.dx;
    } else if (projectedLeft + menuWidth > screenWidth - 12) {
      dx = (screenWidth - 12 - menuWidth) - triggerOffset.dx;
    }

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeDropdown,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(dx, triggerSize.height + 8),
            child: Material(
              color: Colors.transparent,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: menuWidth,
                      child: StatefulBuilder(
                        builder: (ctx, setPanelState) => _buildPanel(setPanelState),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
    _animCtrl.forward(from: 0);
  }

  Future<void> _closeDropdown({bool immediate = false}) async {
    if (!_isOpen && _overlayEntry == null) return;
    if (mounted && !immediate) {
      setState(() => _isOpen = false);
      await _animCtrl.reverse();
    } else {
      _isOpen = false;
    }
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _applyPreset(DateTime start, DateTime end, StateSetter setPanelState) {
    setPanelState(() {
      _draftStart = _dateOnly(start);
      _draftEnd = _dateOnly(end);
      _visibleMonth = DateTime(_draftEnd!.year, _draftEnd!.month);
    });
  }

  void _onDayTap(DateTime tapped, StateSetter setPanelState) {
    final day = _dateOnly(tapped);
    setPanelState(() {
      if (_draftStart == null || (_draftStart != null && _draftEnd != null)) {
        _draftStart = day;
        _draftEnd = null;
      } else {
        if (day.isBefore(_draftStart!)) {
          _draftEnd = _draftStart;
          _draftStart = day;
        } else {
          _draftEnd = day;
        }
      }
    });
  }

  Widget _buildPanel(StateSetter setPanelState) {
    final now = _dateOnly(DateTime.now());
    final firstAllowed = _dateOnly(widget.firstDate ?? DateTime(2020));
    final lastAllowed = _dateOnly(widget.lastDate ?? DateTime(2035));

    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final startWeekday = firstOfMonth.weekday % 7; // 0 = Sunday

    final fmt = DateFormat('MMM d, yyyy');
    final startText = _draftStart != null ? fmt.format(_draftStart!) : 'Pick start';
    final endText = _draftEnd != null ? fmt.format(_draftEnd!) : 'Pick end';
    final canApply = _draftStart != null;

    final cells = <Widget>[];
    for (int i = 0; i < startWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_visibleMonth.year, _visibleMonth.month, d);
      final isDisabled = date.isBefore(firstAllowed) || date.isAfter(lastAllowed);
      final isStart = _draftStart != null && date == _draftStart;
      final isEnd = _draftEnd != null && date == _draftEnd;
      final isInRange = _draftStart != null &&
          _draftEnd != null &&
          date.isAfter(_draftStart!) &&
          date.isBefore(_draftEnd!);
      final isToday = date == now;

      cells.add(
        InkWell(
          onTap: isDisabled ? null : () => _onDayTap(date, setPanelState),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 32,
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: (isStart || isEnd)
                  ? const Color(0xFF2D6A4F)
                  : isInRange
                      ? const Color(0xFF2D6A4F).withValues(alpha: 0.14)
                      : Colors.transparent,
              borderRadius: isStart && isEnd
                  ? BorderRadius.circular(8)
                  : isStart
                      ? const BorderRadius.horizontal(left: Radius.circular(8))
                      : isEnd
                          ? const BorderRadius.horizontal(right: Radius.circular(8))
                          : isInRange
                              ? BorderRadius.zero
                              : BorderRadius.circular(8),
              border: isToday && !isStart && !isEnd
                  ? Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.55))
                  : null,
            ),
            child: Center(
              child: Text(
                '$d',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: (isStart || isEnd || isToday) ? FontWeight.w700 : FontWeight.w500,
                  color: isDisabled
                      ? Colors.grey.shade300
                      : (isStart || isEnd)
                          ? Colors.white
                          : isInRange
                              ? const Color(0xFF1B4332)
                              : const Color(0xFF1E293B),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final totalRows = (cells.length + 6) ~/ 7;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Quick Presets
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _presetChip('Last 7 Days', () {
                _applyPreset(now.subtract(const Duration(days: 6)), now, setPanelState);
              }),
              _presetChip('Last 30 Days', () {
                _applyPreset(now.subtract(const Duration(days: 29)), now, setPanelState);
              }),
              _presetChip('This Month', () {
                _applyPreset(DateTime(now.year, now.month, 1), now, setPanelState);
              }),
              _presetChip('Last Month', () {
                final firstPrev = DateTime(now.year, now.month - 1, 1);
                final lastPrev = DateTime(now.year, now.month, 0);
                _applyPreset(firstPrev, lastPrev, setPanelState);
              }),
            ],
          ),
          const SizedBox(height: 10),

          // Selected Range Summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    startText,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF1B4332)),
                    textAlign: TextAlign.center,
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF64748B)),
                Expanded(
                  child: Text(
                    endText,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _draftEnd != null ? const Color(0xFF1B4332) : Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Month Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () {
                  setPanelState(() {
                    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
                  });
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(_visibleMonth),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () {
                  setPanelState(() {
                    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Weekday Headers
          Row(
            children: const ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),

          // Day Grid
          ...List.generate(totalRows, (r) {
            return Row(
              children: List.generate(7, (c) {
                final idx = r * 7 + c;
                return Expanded(child: idx < cells.length ? cells[idx] : const SizedBox.shrink());
              }),
            );
          }),

          const SizedBox(height: 10),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 8),

          // Footer Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _closeDropdown,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: canApply
                    ? () async {
                        final start = _draftStart!;
                        final end = _draftEnd ?? _draftStart!;
                        await _closeDropdown();
                        widget.onRangeSelected(DateTimeRange(start: start, end: end));
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D6A4F),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                ),
                child: const Text('Apply Range', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF2D6A4F).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2D6A4F).withValues(alpha: 0.25)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1B4332)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleDropdown,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.date_range_outlined, size: 15, color: Color(0xFF2D6A4F)),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: const Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: Color(0xFF2D6A4F)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
