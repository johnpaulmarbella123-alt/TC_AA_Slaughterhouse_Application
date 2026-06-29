import 'package:flutter/material.dart';

class GalleryContent extends StatefulWidget {
  const GalleryContent({super.key});

  @override
  State<GalleryContent> createState() => _GalleryContentState();
}

class _GalleryContentState extends State<GalleryContent> {
  String _selectedFilter = 'All Photos';

  final List<String> _filters = ['All Photos', 'Facility', 'Team', 'Livestock'];

  // All images with their category
  final List<Map<String, String>> _allImages = [
    // Facility
    {'path': 'assets/images/pic1.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic2.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic3.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic4.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic5.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic6.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic7.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic8.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic9.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic10.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic11.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic12.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic13.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic14.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic15.jpeg', 'category': 'Facility'},
    {'path': 'assets/images/pic16.jpeg', 'category': 'Facility'},
    // Team
    {'path': 'assets/images/Team.jpg', 'category': 'Team'},
    {'path': 'assets/images/team1.jpg', 'category': 'Team'},
    {'path': 'assets/images/team2.jpg', 'category': 'Team'},
    {'path': 'assets/images/team3.jpg', 'category': 'Team'},
    {'path': 'assets/images/Team4.jpg', 'category': 'Team'},
    {'path': 'assets/images/team5.jpg', 'category': 'Team'},
    // Livestock
    {'path': 'assets/images/hog.jpg', 'category': 'Livestock'},
    {'path': 'assets/images/cow.jpg', 'category': 'Livestock'},
    {'path': 'assets/images/Goat.jpg', 'category': 'Livestock'},
    {'path': 'assets/images/Sheep.jpg', 'category': 'Livestock'},
    {'path': 'assets/images/Cara.jpg', 'category': 'Livestock'},
  ];

  List<Map<String, String>> get _filteredImages {
    if (_selectedFilter == 'All Photos') return _allImages;
    return _allImages.where((img) => img['category'] == _selectedFilter).toList();
  }

  void _openFullscreen(BuildContext context, int index) {
    final images = _filteredImages;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenGallery(images: images, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
            "Take a look at our modern facilities, professional operators & veterinarians",
            style: TextStyle(color: Colors.white, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),

        // Filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((filter) {
                final isSelected = _selectedFilter == filter;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilter = filter),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1E855A) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF1E855A) : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      filter,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Image grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: _filteredImages.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => _openFullscreen(context, index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    _filteredImages[index]['path']!,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── FULLSCREEN VIEWER ────────────────────────────────────────────────────────
class _FullscreenGallery extends StatefulWidget {
  final List<Map<String, String>> images;
  final int initialIndex;

  const _FullscreenGallery({required this.images, required this.initialIndex});

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Center(
              child: Image.asset(
                widget.images[index]['path']!,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}