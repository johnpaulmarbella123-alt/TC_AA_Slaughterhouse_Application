import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReviewContent extends StatefulWidget {
  const ReviewContent({super.key});

  @override
  State<ReviewContent> createState() => _ReviewContentState();
}

class _ReviewContentState extends State<ReviewContent> {
  List<Map<String, dynamic>> _reviews = [];
  bool _loading = true;
  bool _showAll = false;

  // Rating summary
  double _averageRating = 0;
  int _totalReviews = 0;
  Map<int, int> _ratingCounts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final data = await Supabase.instance.client
          .from('reviews')
          .select()
          .order('created_at', ascending: false);

      final reviews = List<Map<String, dynamic>>.from(data);

      // Calculate rating stats
      Map<int, int> counts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
      double total = 0;
      for (var r in reviews) {
        int rating = (r['rating'] as num).toInt();
        counts[rating] = (counts[rating] ?? 0) + 1;
        total += rating;
      }

      setState(() {
        _reviews = reviews;
        _totalReviews = reviews.length;
        _averageRating = reviews.isEmpty ? 0 : total / reviews.length;
        _ratingCounts = counts;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('Error loading reviews: $e');
    }
  }

  void _openWriteReview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WriteReviewSheet(onSubmitted: _loadReviews),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _avatarColor(String name) {
    final colors = [
      const Color(0xFF1E855A),
      const Color(0xFF1565C0),
      const Color(0xFFD4A017),
      const Color(0xFFE53935),
      const Color(0xFF6A1B9A),
    ];
    return colors[name.length % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final displayedReviews = _showAll ? _reviews : _reviews.take(3).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E855A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              "What our satisfied customers are saying about us",
              style: TextStyle(color: Colors.white, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),

          // Rating summary
          if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Average score
                  Column(
                    children: [
                      Text(
                        _averageRating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _buildStars(_averageRating),
                      const SizedBox(height: 4),
                      Text(
                        '$_totalReviews Viewers',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  // Bar breakdown
                  Expanded(
                    child: Column(
                      children: [5, 4, 3, 2, 1].map((star) {
                        final count = _ratingCounts[star] ?? 0;
                        final fraction = _totalReviews > 0 ? count / _totalReviews : 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Text('$star', style: const TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              const Icon(Icons.star, size: 12, color: Color(0xFFFFC107)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: fraction.toDouble(),
                                    backgroundColor: Colors.grey.shade200,
                                    color: const Color(0xFFFFC107),
                                    minHeight: 8,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('$count', style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Write a Review button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openWriteReview,
                icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
                label: const Text(
                  'Write a Review',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E855A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Review cards
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_reviews.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Text('No reviews yet. Be the first to review!',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...displayedReviews.map((review) => _buildReviewCard(review)).toList(),

          // See All / Show Less button
          if (_reviews.length > 3)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(
                  _showAll ? 'Show Less' : 'See All Reviews',
                  style: const TextStyle(color: Color(0xFF1E855A)),
                ),
              ),
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final name = review['reviewer_name'] ?? 'Anonymous';
    final rating = (review['rating'] as num).toDouble();
    final comment = review['comment'] ?? '';
    final service = review['service_type'] ?? '';
    final date = review['created_at'] != null
        ? DateTime.tryParse(review['created_at'])
        : null;
    final helpful = review['helpful_count'] ?? 0;
    final dateStr = date != null
        ? '${_monthName(date.month)} ${date.day}, ${date.year}'
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _avatarColor(name),
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  Row(
                    children: [
                      _buildStars(rating),
                      const SizedBox(width: 6),
                      Text(
                        '$dateStr${service.isNotEmpty ? ' • $service' : ''}',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(comment, style: const TextStyle(fontSize: 12, color: Colors.black87)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.thumb_up_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text('Helpful ($helpful)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (i < rating.floor()) {
          return const Icon(Icons.star, size: 14, color: Color(0xFFFFC107));
        } else if (i < rating) {
          return const Icon(Icons.star_half, size: 14, color: Color(0xFFFFC107));
        } else {
          return const Icon(Icons.star_border, size: 14, color: Color(0xFFFFC107));
        }
      }),
    );
  }

  String _monthName(int month) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month];
  }
}

// ── WRITE REVIEW BOTTOM SHEET ────────────────────────────────────────────────
class _WriteReviewSheet extends StatefulWidget {
  final VoidCallback onSubmitted;
  const _WriteReviewSheet({required this.onSubmitted});

  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  int _selectedRating = 0;
  String _selectedService = 'Pig Slaughter';
  final _nameController = TextEditingController();
  final _commentController = TextEditingController();
  bool _submitting = false;

  final List<String> _services = [
    'Pig Slaughter',
    'Cattle Slaughter',
    'Goat Slaughter',
    'Sheep Slaughter',
    'Carabao Slaughter',
  ];

  Future<void> _submit() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating')),
      );
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }
    if (_commentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write your review')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      await Supabase.instance.client.from('reviews').insert({
        'reviewer_name': _nameController.text.trim(),
        'rating': _selectedRating,
        'comment': _commentController.text.trim(),
        'service_type': _selectedService,
        'helpful_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        Navigator.pop(context);
        widget.onSubmitted();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review submitted successfully!'),
            backgroundColor: Color(0xFF1E855A),
          ),
        );
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Write a Review',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Star rating
            const Text('Your Rating', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (i) {
                return GestureDetector(
                  onTap: () => setState(() => _selectedRating = i + 1),
                  child: Icon(
                    i < _selectedRating ? Icons.star : Icons.star_border,
                    color: const Color(0xFFFFC107),
                    size: 36,
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // Name
            const Text('Your Name', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Enter your full name',
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Service type
            const Text('Service Type', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedService,
                  isExpanded: true,
                  items: _services
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedService = v!),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Comment
            const Text('Your Review', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Share your experience...',
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E855A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Submit Review',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}