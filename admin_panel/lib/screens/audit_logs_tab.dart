import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/audit_log_service.dart';
import '../services/csv_export_helper.dart';

/// Admin-only immutable Staff Activity & Audit Trail Viewer (`public.audit_logs`).
class AuditLogsTab extends StatefulWidget {
  final DateTimeRange? activeDateRange;
  const AuditLogsTab({super.key, this.activeDateRange});

  @override
  State<AuditLogsTab> createState() => _AuditLogsTabState();
}

class _AuditLogsTabState extends State<AuditLogsTab> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = [];

  String _moduleFilter = 'All';
  String _searchQuery = '';
  bool _useActiveDateRange = false;

  static const List<String> _modules = [
    'All',
    'Receiving',
    'Document Verification',
    'Slaughter & Inspection',
    'Payment & Cashiering',
    'Meat Releasing',
    'Meat Dealers',
    'Settings',
    'Staff & Roles',
  ];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void didUpdateWidget(AuditLogsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_useActiveDateRange && oldWidget.activeDateRange != widget.activeDateRange) {
      _loadLogs();
    }
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final rows = await AuditLogService.instance.fetchLogs(
        range: _useActiveDateRange ? widget.activeDateRange : null,
        module: _moduleFilter,
        search: _searchQuery,
      );
      if (mounted) {
        setState(() {
          _logs = rows;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to load audit logs. Ensure the 20261120_audit_logs_and_cancellation.sql migration has been applied in Supabase.\nDetails: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _formatTimestamp(dynamic raw) {
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return raw.toString();
    return DateFormat('yyyy-MM-dd hh:mm:ss a').format(dt);
  }

  String _formatDetails(dynamic raw) {
    if (raw == null) return '—';
    if (raw is Map) {
      if (raw.isEmpty) return '—';
      return raw.entries.map((e) => '${e.key}: ${e.value}').join(' • ');
    }
    return raw.toString();
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return const Color(0xFF1B4332);
      case 'inspector':
        return const Color(0xFF7C3AED);
      case 'clerk':
      case 'cashier':
        return const Color(0xFF0369A1);
      default:
        return const Color(0xFF475569);
    }
  }

  Future<void> _exportCsv() async {
    final headers = [
      'Timestamp',
      'Actor Name',
      'Actor Email',
      'Role',
      'Module',
      'Action',
      'Target Ref',
      'Target ID',
      'Details',
    ];
    final rows = _logs.map((row) {
      return [
        _formatTimestamp(row['created_at']),
        row['actor_name'] ?? '',
        row['actor_email'] ?? '',
        row['actor_role'] ?? '',
        row['module'] ?? '',
        row['action'] ?? '',
        row['target_ref'] ?? '',
        row['target_id'] ?? '',
        _formatDetails(row['details']),
      ];
    }).toList();

    final stamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    final ok = await downloadCsvFile(
      filename: 'TCAA_Audit_Logs_$stamp.csv',
      headers: headers,
      rows: rows,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Audit Logs CSV exported (${_logs.length} records).' : 'Failed to export CSV.'),
          backgroundColor: ok ? const Color(0xFF2D6A4F) : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Info + Filter Controls
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.verified_user_outlined, color: Color(0xFF1B4332), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Immutable Staff Audit Trail',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A202C)),
                        ),
                        Text(
                          'Tamper-evident log of approvals, inspections, cash verifications, releases, and system changes (Admin-Only)',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _logs.isEmpty ? null : _exportCsv,
                    icon: const Icon(Icons.table_view_outlined, size: 16, color: Colors.white),
                    label: const Text('Export CSV', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D6A4F),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF2F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _moduleFilter,
                        items: _modules
                            .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12.5))))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _moduleFilter = val);
                            _loadLogs();
                          }
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    height: 38,
                    child: TextField(
                      onChanged: (v) {
                        _searchQuery = v;
                        _loadLogs();
                      },
                      decoration: InputDecoration(
                        hintText: 'Search staff, ref no, action...',
                        hintStyle: const TextStyle(fontSize: 12.5),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Apply Report Date Filter', style: TextStyle(fontSize: 12)),
                    selected: _useActiveDateRange,
                    selectedColor: const Color(0xFF2D6A4F).withValues(alpha: 0.15),
                    onSelected: (v) {
                      setState(() => _useActiveDateRange = v);
                      _loadLogs();
                    },
                  ),
                  IconButton(
                    onPressed: _loadLogs,
                    tooltip: 'Refresh audit logs',
                    icon: const Icon(Icons.refresh, color: Color(0xFF2D6A4F)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator(color: Color(0xFF2D6A4F))),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade800),
                const SizedBox(width: 12),
                Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: Colors.orange.shade900))),
              ],
            ),
          )
        else if (_logs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.history_toggle_off, size: 46, color: Colors.grey.shade400),
                const SizedBox(height: 10),
                Text(
                  'No audit log entries recorded yet for this filter.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                dataRowMinHeight: 48,
                dataRowMaxHeight: 72,
                columns: const [
                  DataColumn(label: Text('Timestamp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                  DataColumn(label: Text('Staff / Actor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                  DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                  DataColumn(label: Text('Module', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                  DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                  DataColumn(label: Text('Reference', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                  DataColumn(label: Text('Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5))),
                ],
                rows: _logs.map((row) {
                  final role = (row['actor_role'] ?? 'Staff').toString();
                  final roleColor = _roleColor(role);
                  return DataRow(
                    cells: [
                      DataCell(Text(_formatTimestamp(row['created_at']), style: const TextStyle(fontSize: 12))),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (row['actor_name'] ?? 'Staff').toString(),
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              (row['actor_email'] ?? '').toString(),
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: roleColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            role,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: roleColor),
                          ),
                        ),
                      ),
                      DataCell(Text((row['module'] ?? '').toString(), style: const TextStyle(fontSize: 12))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDF2F7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            (row['action'] ?? '').toString(),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataCell(Text((row['target_ref'] ?? row['target_id'] ?? '—').toString(), style: const TextStyle(fontSize: 12))),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Text(
                            _formatDetails(row['details']),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }
}
