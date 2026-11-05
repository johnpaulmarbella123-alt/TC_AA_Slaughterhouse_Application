import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WalkInClaimHelper {
  /// Shows the dialog to claim/link an active walk-in slip or permanent dealer marking tag.
  static Future<bool> showClaimDialog(
    BuildContext context, {
    VoidCallback? onClaimSuccess,
  }) async {
    final codeCtrl = TextEditingController();
    bool isClaiming = false;
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !isClaiming,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_link, color: Color(0xFF1E855A)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Claim & Link Walk-In Order',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the Reference Number (e.g., MI-2026-005) or Permanent Marking Tag (e.g., 99 or MK-1) from your abattoir claim stub. Once linked, your profile will be verified and your permanent marking will be locked for all future slaughter requests.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Reference No. or Marking Tag',
                    hintText: 'e.g. MI-2026-114 or 99',
                    errorText: errorText,
                    filled: true,
                    fillColor: const Color(0xFFF7FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isClaiming ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isClaiming
                  ? null
                  : () async {
                      final raw = codeCtrl.text.trim();
                      if (raw.isEmpty) {
                        setDlgState(() => errorText = 'Please enter your Reference No. or Marking Tag');
                        return;
                      }
                      final supabase = Supabase.instance.client;
                      final user = supabase.auth.currentUser;
                      if (user == null) return;

                      setDlgState(() {
                        isClaiming = true;
                        errorText = null;
                      });

                      try {
                        Map<String, dynamic>? matchedReq;
                        final upper = raw.toUpperCase();
                        final idMatch = RegExp(r'(?:MI-\d{4}-|RCP-\d{4}-|^)(\d+)$').firstMatch(upper);
                        final int? parsedId = idMatch != null ? int.tryParse(idMatch.group(1)!) : null;

                        // 1. Check in `requests` table
                        try {
                          if (parsedId != null) {
                            final res = await supabase
                                .from('requests')
                                .select('*, slaughter_inspection(*)')
                                .eq('id', parsedId)
                                .maybeSingle();
                            if (res != null) matchedReq = Map<String, dynamic>.from(res);
                          }

                          if (matchedReq == null) {
                            final byMarking = await supabase
                                .from('requests')
                                .select('*, slaughter_inspection(*)')
                                .ilike('marking', raw)
                                .order('created_at', ascending: false)
                                .limit(1);
                            if ((byMarking as List).isNotEmpty) {
                              matchedReq = Map<String, dynamic>.from(byMarking.first);
                            }
                          }
                        } catch (_) {}

                        // 2. Fallback: check `walk_in_directory` in `system_settings`
                        if (matchedReq == null) {
                          try {
                            final dirRow = await supabase
                                .from('system_settings')
                                .select('value')
                                .eq('key', 'walk_in_directory')
                                .maybeSingle();
                            if (dirRow != null && dirRow['value'] is List) {
                              final dirList = List<dynamic>.from(dirRow['value']);
                              for (int i = 0; i < dirList.length; i++) {
                                final item = dirList[i];
                                if (item is Map) {
                                  final itemId = int.tryParse(item['id']?.toString() ?? '');
                                  final itemMarking = (item['marking'] ?? item['customer_marking'] ?? '').toString().trim();
                                  final itemRef = itemId != null
                                      ? 'MI-${DateTime.now().year}-${itemId.toString().padLeft(3, '0')}'
                                      : '';
                                  final idMatches = parsedId != null && itemId == parsedId;
                                  final markingMatches = itemMarking.isNotEmpty &&
                                      itemMarking.toLowerCase() == raw.toLowerCase();
                                  final refMatches = itemRef.isNotEmpty &&
                                      itemRef.toUpperCase() == upper;

                                  if (idMatches || markingMatches || refMatches) {
                                    matchedReq = Map<String, dynamic>.from(item);
                                    matchedReq['user_id'] = user.id;
                                    dirList[i] = matchedReq;
                                    try {
                                      await supabase.from('system_settings').upsert({
                                        'key': 'walk_in_directory',
                                        'value': dirList,
                                      }, onConflict: 'key');
                                    } catch (_) {}
                                    break;
                                  }
                                }
                              }
                            }
                          } catch (_) {}
                        }

                        // Determine resolved marking and official dealer name
                        String resolvedMarking = '';
                        String resolvedOfficialName = '';

                        if (matchedReq != null) {
                          resolvedMarking = (matchedReq['marking'] ?? matchedReq['customer_marking'] ?? '').toString().trim();
                          resolvedOfficialName = (matchedReq['customer_name'] ?? '').toString().trim();
                        } else {
                          // 3. Fallback: Lookup directly in regular_dealers registry
                          resolvedMarking = raw.toUpperCase();
                        }

                        // Check official regular_dealers registry in system_settings
                        try {
                          final regRow = await supabase
                              .from('system_settings')
                              .select('value')
                              .eq('key', 'regular_dealers')
                              .maybeSingle();

                          if (regRow != null && regRow['value'] is List) {
                            final regList = List<dynamic>.from(regRow['value']);
                            bool listChanged = false;

                            for (int i = 0; i < regList.length; i++) {
                              final dealer = regList[i];
                              if (dealer is Map) {
                                final dName = (dealer['name'] ?? '').toString().trim().toUpperCase();
                                final dMark = (dealer['markings'] ?? dealer['marking'] ?? '').toString().trim().toUpperCase();

                                final matchesMarking = resolvedMarking.isNotEmpty && dMark == resolvedMarking.toUpperCase();
                                final matchesName = resolvedOfficialName.isNotEmpty &&
                                    (dName == resolvedOfficialName.toUpperCase() ||
                                     resolvedOfficialName.toUpperCase().contains(dName) ||
                                     dName.contains(resolvedOfficialName.toUpperCase()));
                                final matchesInput = raw.toUpperCase() == dMark || raw.toUpperCase() == dName;

                                if (matchesMarking || matchesName || matchesInput) {
                                  resolvedOfficialName = dName;
                                  resolvedMarking = dMark;

                                  final updatedDealer = Map<String, dynamic>.from(dealer);
                                  updatedDealer['user_id'] = user.id;
                                  regList[i] = updatedDealer;
                                  listChanged = true;
                                  break;
                                }
                              }
                            }

                            if (listChanged) {
                              try {
                                await supabase.from('system_settings').upsert({
                                  'key': 'regular_dealers',
                                  'value': regList,
                                }, onConflict: 'key');
                              } catch (_) {}
                            }
                          }
                        } catch (_) {}

                        if (matchedReq == null && resolvedOfficialName.isEmpty) {
                          setDlgState(() {
                            isClaiming = false;
                            errorText = 'No walk-in order or registered dealer found with that Reference No. or Marking.';
                          });
                          return;
                        }

                        // 4. Update profile with locked official dealer name and permanent marking
                        try {
                          final profileUpdates = <String, dynamic>{
                            'assigned_marking': resolvedMarking,
                            'marking_locked': true,
                            'customer_type': 'regular',
                          };
                          if (resolvedOfficialName.isNotEmpty) {
                            profileUpdates['display_name'] = resolvedOfficialName;
                            profileUpdates['official_dealer_name'] = resolvedOfficialName;
                          }
                          await supabase.from('profiles').update(profileUpdates).eq('id', user.id);
                        } catch (_) {}

                        // 5. If matched to a specific request ID, link request, payments & claims
                        if (matchedReq != null && matchedReq['id'] != null) {
                          final reqId = matchedReq['id'];

                          try {
                            final claimsRow = await supabase
                                .from('system_settings')
                                .select('value')
                                .eq('key', 'walk_in_claims')
                                .maybeSingle();
                            final Map<String, dynamic> claimsMap =
                                (claimsRow != null && claimsRow['value'] is Map)
                                    ? Map<String, dynamic>.from(claimsRow['value'])
                                    : <String, dynamic>{};
                            claimsMap[reqId.toString()] = user.id;
                            await supabase.from('system_settings').upsert({
                              'key': 'walk_in_claims',
                              'value': claimsMap,
                            }, onConflict: 'key');
                          } catch (_) {}

                          try {
                            await supabase
                                .from('requests')
                                .update({'user_id': user.id})
                                .eq('id', reqId);
                          } catch (_) {}

                          try {
                            await supabase
                                .from('payments')
                                .update({'user_id': user.id})
                                .eq('request_id', reqId);
                          } catch (_) {}

                          // Insert status notification
                          final status = (matchedReq['status'] ?? 'approved').toString();
                          final livestock = matchedReq['livestock_type'] ?? 'Livestock';
                          final count = matchedReq['animal_count'] ?? 1;
                          final refStr = 'MI-${DateTime.now().year}-${reqId.toString().padLeft(3, '0')}';

                          String notifTitle = 'Walk-In Order Linked ($refStr)';
                          String notifMsg = 'Your order for $count head(s) of $livestock is linked. Verified Dealer: $resolvedOfficialName (Tag: $resolvedMarking).';
                          String notifType = 'request_approved';

                          if (status == 'anti_mortem_failed') {
                            notifTitle = '$livestock — Health Issue Detected';
                            notifMsg = 'Ante-mortem inspection failed. Please tap Respond to choose whether to Confine or Take Back your livestock.';
                            notifType = 'anti_mortem_failed';
                          } else if (status == 'releasable' || status == 'mic_generated') {
                            notifTitle = 'Slaughter Operation Complete';
                            notifMsg = 'Your $count head(s) of $livestock ($refStr) passed post-mortem inspection and is ready for payment and release.';
                            notifType = 'slaughter_completed';
                          }

                          try {
                            await supabase.from('notifications').insert({
                              'user_id': user.id,
                              'title': notifTitle,
                              'message': notifMsg,
                              'type': notifType,
                              'is_read': false,
                              'data': {
                                'request_id': reqId,
                                'livestock_type': livestock,
                                'animal_count': count,
                              },
                            });
                          } catch (_) {}
                        }

                        if (ctx.mounted) Navigator.pop(ctx, true);
                        onClaimSuccess?.call();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.verified, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      resolvedOfficialName.isNotEmpty
                                          ? 'Verified as Regular Dealer: $resolvedOfficialName • Marking: $resolvedMarking'
                                          : 'Linked marking: $resolvedMarking (Permanently locked)',
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: const Color(0xFF1E855A),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                      } catch (e) {
                        setDlgState(() {
                          isClaiming = false;
                          errorText = 'Could not link order: $e';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E855A),
                foregroundColor: Colors.white,
              ),
              child: isClaiming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Link Order'),
            ),
          ],
        ),
      ),
    );

    return result == true;
  }
}

