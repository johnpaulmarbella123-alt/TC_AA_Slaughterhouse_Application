import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Standalone Customer Reviews & Feedback view embedded inside Reports & Records.
class CustomerReviewsView extends StatefulWidget {
  const CustomerReviewsView({super.key});

  @override
  State<CustomerReviewsView> createState() => _CustomerReviewsViewState();
}

class _CustomerReviewsViewState extends State<CustomerReviewsView> {
  List<Map<String, dynamic>> _adminReviews = [];
  bool _loadingReviews = false;
  String _reviewSearchQuery = '';
  int? _selectedStarFilter; // null = all
  final TextEditingController _reviewSearchCtrl = TextEditingController();
  double _reviewAverageRating = 0.0;
  Map<int, int> _reviewRatingCounts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
  double _reviewBlendedSatisfaction = 0.0;
  int _reviewCompletedOrdersCount = 0;
  int _reviewTotalOrdersCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAdminReviews();
  }

  @override
  void dispose() {
    _reviewSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAdminReviews() async {
    setState(() => _loadingReviews = true);
    try {
      final client = Supabase.instance.client;
      final data = await client
          .from('reviews')
          .select()
          .order('created_at', ascending: false);
      final reviews = List<Map<String, dynamic>>.from(data);

      final Map<int, int> counts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
      double totalRating = 0;
      for (final r in reviews) {
        final rating = (r['rating'] as num?)?.toInt() ?? 5;
        counts[rating] = (counts[rating] ?? 0) + 1;
        totalRating += rating;
      }
      final avg = reviews.isEmpty ? 0.0 : (totalRating / reviews.length);

      int completed = 0;
      int total = 0;
      double compRate = 0.0;
      try {
        final reqData = await client.from('requests').select('status');
        final reqList = List<Map<String, dynamic>>.from(reqData);
        for (final r in reqList) {
          final s = (r['status'] ?? '').toString().toLowerCase();
          if (s != 'cancelled' && s != 'rejected') {
            total++;
            if (s == 'released' || s == 'completed') {
              completed++;
            }
          }
        }
        if (total > 0) {
          compRate = (completed / total) * 100.0;
        }
      } catch (err) {
        debugPrint('Could not fetch requests for satisfaction rate: $err');
      }

      final double revScore = reviews.isNotEmpty ? (avg / 5.0) * 100.0 : 0.0;
      final double blended = (0.50 * compRate) + (0.50 * revScore);

      if (mounted) {
        setState(() {
          _adminReviews = reviews;
          _reviewAverageRating = avg;
          _reviewRatingCounts = counts;
          _reviewCompletedOrdersCount = completed;
          _reviewTotalOrdersCount = total;
          _reviewBlendedSatisfaction = blended.clamp(0.0, 100.0);
          _loadingReviews = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading customer reviews: $e');
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reviews = _adminReviews;
    final filteredReviews = reviews.where((r) {
      if (_selectedStarFilter != null) {
        final rating = (r['rating'] as num?)?.toInt() ?? 0;
        if (rating != _selectedStarFilter) return false;
      }
      if (_reviewSearchQuery.isNotEmpty) {
        final q = _reviewSearchQuery.toLowerCase();
        final name = (r['reviewer_name'] ?? '').toString().toLowerCase();
        final comment = (r['comment'] ?? '').toString().toLowerCase();
        final service = (r['service_type'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !comment.contains(q) && !service.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header Row ──
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customer Reviews & Feedback',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reviews submitted by registered mobile app customers. Blended dynamically with order completion rates for the official public satisfaction index.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loadingReviews ? null : _loadAdminReviews,
              icon: _loadingReviews
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2D6A4F),
                side: const BorderSide(color: Color(0xFF2D6A4F)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Top Summary Cards (Responsive) ──
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 850;
            final cards = [
              _buildReviewMetricCard(
                isDark: isDark,
                title: 'Average Customer Rating',
                value: _reviewAverageRating > 0
                    ? _reviewAverageRating.toStringAsFixed(1)
                    : '0.0',
                subtitle:
                    '${reviews.length} customer ${reviews.length == 1 ? "review" : "reviews"} recorded',
                extraWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (index) {
                    final starVal = index + 1;
                    return Icon(
                      starVal <= _reviewAverageRating.round()
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: const Color(0xFFF59E0B),
                      size: 20,
                    );
                  }),
                ),
              ),
              _buildStarDistributionCard(isDark),
              _buildSatisfactionCard(isDark),
            ];

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 16),
                  Expanded(child: cards[1]),
                  const SizedBox(width: 16),
                  Expanded(child: cards[2]),
                ],
              );
            } else {
              return Column(
                children: [
                  cards[0],
                  const SizedBox(height: 14),
                  cards[1],
                  const SizedBox(height: 14),
                  cards[2],
                ],
              );
            }
          },
        ),
        const SizedBox(height: 24),

        // ── Filter & Search Toolbar Card ──
        Card(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reviewSearchCtrl,
                        onChanged: (val) {
                          setState(() => _reviewSearchQuery = val.trim());
                        },
                        decoration: InputDecoration(
                          hintText: 'Search by customer name, comment, or service...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade400,
                          ),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _reviewSearchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  onPressed: () {
                                    _reviewSearchCtrl.clear();
                                    setState(() => _reviewSearchQuery = '');
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : Colors.grey.shade300,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF2D6A4F),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        'Filter by rating: ',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStarFilterChip(
                        label: 'All (${reviews.length})',
                        isSelected: _selectedStarFilter == null,
                        onTap: () => setState(() => _selectedStarFilter = null),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 6),
                      ...[5, 4, 3, 2, 1].map((stars) {
                        final count = _reviewRatingCounts[stars] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _buildStarFilterChip(
                            label: '$stars ★ ($count)',
                            isSelected: _selectedStarFilter == stars,
                            onTap: () {
                              setState(() {
                                _selectedStarFilter =
                                    _selectedStarFilter == stars ? null : stars;
                              });
                            },
                            isDark: isDark,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Reviews List Section ──
        if (_loadingReviews)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF2D6A4F)),
            ),
          )
        else if (filteredReviews.isEmpty)
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 20),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 56,
                      color: isDark ? const Color(0xFF475569) : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      reviews.isEmpty
                          ? 'No customer reviews submitted yet'
                          : 'No customer reviews match your filters',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      reviews.isEmpty
                          ? 'Customer reviews submitted through the mobile app will be displayed and audited here.'
                          : 'Try adjusting your search terms or star rating filter to view more reviews.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Column(
            children: filteredReviews.map((review) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildReviewCard(review, isDark),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildStarFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2D6A4F)
              : (isDark ? const Color(0xFF0F172A) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2D6A4F)
                : (isDark ? const Color(0xFF334155) : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildReviewMetricCard({
    required bool isDark,
    required String title,
    required String value,
    required String subtitle,
    Widget? extraWidget,
  }) {
    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                if (value != '0.0') ...[
                  const SizedBox(width: 4),
                  Text(
                    '/ 5.0',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
                    ),
                  ),
                ],
              ],
            ),
            if (extraWidget != null) ...[
              const SizedBox(height: 6),
              extraWidget,
            ],
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarDistributionCard(bool isDark) {
    final total = _adminReviews.length;
    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rating Breakdown',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            ...[5, 4, 3, 2, 1].map((star) {
              final count = _reviewRatingCounts[star] ?? 0;
              final percent = total > 0 ? (count / total) : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '$star★',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFCBD5E1) : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 6,
                          backgroundColor: isDark
                              ? const Color(0xFF334155)
                              : Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 24,
                      child: Text(
                        '$count',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSatisfactionCard(bool isDark) {
    final compRate = _reviewTotalOrdersCount > 0
        ? (_reviewCompletedOrdersCount / _reviewTotalOrdersCount) * 100.0
        : 0.0;
    final reviewPct = (_reviewAverageRating / 5.0) * 100.0;

    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Public Satisfaction Index',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Live Formula',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D6A4F),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${_reviewBlendedSatisfaction.toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2D6A4F),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '50% Customer Reviews (${reviewPct.toStringAsFixed(0)}%) + 50% Completed Orders (${compRate.toStringAsFixed(0)}%)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Automatically synchronized with the Dashboard KPI card.',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: isDark ? const Color(0xFF64748B) : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review, bool isDark) {
    final name = (review['reviewer_name'] ?? 'Verified Customer').toString();
    final rating = (review['rating'] as num?)?.toInt() ?? 5;
    final comment = (review['comment'] ?? '').toString().trim();
    final service = (review['service_type'] ?? '').toString().trim();
    final helpfulCount = (review['helpful_count'] as num?)?.toInt() ?? 0;

    String dateStr = 'Recently';
    if (review['created_at'] != null) {
      final parsed = DateTime.tryParse(review['created_at'].toString());
      if (parsed != null) {
        dateStr = DateFormat('MMM d, yyyy • h:mm a').format(parsed.toLocal());
      }
    }

    final initials = _extractInitials(name);

    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF2D6A4F).withValues(alpha: 0.12),
                  child: Text(
                    initials,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2D6A4F),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D6A4F).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 11, color: Color(0xFF2D6A4F)),
                                SizedBox(width: 3),
                                Text(
                                  'Customer App',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2D6A4F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(5, (idx) {
                              return Icon(
                                idx < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: const Color(0xFFF59E0B),
                                size: 16,
                              );
                            }),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (service.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 13,
                          color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          service,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFCBD5E1) : Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
                ),
              ),
              child: Text(
                comment.isNotEmpty ? comment : 'No written feedback provided.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontStyle: comment.isEmpty ? FontStyle.italic : FontStyle.normal,
                  color: comment.isEmpty
                      ? (isDark ? const Color(0xFF64748B) : Colors.grey.shade500)
                      : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.thumb_up_alt_outlined,
                  size: 14,
                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  '$helpfulCount people found this helpful',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
                  ),
                ),
                const Spacer(),
                if (review['id'] != null)
                  Text(
                    'Review #${review['id']}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: isDark ? const Color(0xFF64748B) : Colors.grey.shade400,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _extractInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'C';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return trimmed.substring(0, 1).toUpperCase();
  }
}
