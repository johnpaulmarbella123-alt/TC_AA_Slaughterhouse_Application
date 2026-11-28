import 'package:flutter/material.dart';

class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isNarrowPhone = width < 400;
    final isPhone = width < 600;
    final isTablet = width >= 600 && width < 900;

    final double headlineSize = isNarrowPhone
        ? 23
        : (isPhone ? 27 : (isTablet ? 36 : 45));
    final double subtitleSize = isPhone ? 13 : (isTablet ? 14 : 15);
    final double horizontalPad = isPhone ? 20 : 32;
    final double buttonTopGap = isPhone ? 28 : (isTablet ? 40 : 56);

    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset('assets/images/BG.jpeg', fit: BoxFit.cover),
          ),
          // Dark Overlay
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.50)),
          ),
          // Safe Column Layout (Header never overlaps Hero content on any screen size)
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(isPhone: isPhone),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPad,
                          vertical: isPhone ? 12 : 24,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                isPhone
                                    ? 'Tabaco City Slaughterhouse\nSafe, clean, and quality livestock processing for all community "AA".'
                                    : 'Tabaco City Slaughterhouse\nSafe, clean, and quality livestock processing\nfor all community "AA".',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: headlineSize,
                                  fontWeight: isPhone ? FontWeight.w400 : FontWeight.w300,
                                  height: isPhone ? 1.25 : 1.15,
                                ),
                              ),
                              SizedBox(height: isPhone ? 14 : 24),
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: isPhone ? 360 : 600),
                                child: Text(
                                  'Tabaco City provides safe and hygienic livestock processing. As a government-regulated facility, we follow strict food safety and environmental standards to ensure quality meat products and reliable service for the community.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: subtitleSize,
                                    fontWeight: FontWeight.w400,
                                    height: 1.55,
                                  ),
                                ),
                              ),
                              SizedBox(height: buttonTopGap),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 260),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () => Navigator.pushNamed(context, '/login'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F5132),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: isPhone ? 14 : 16,
                                      ),
                                      elevation: 3,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      'Sign In to Abattoir System',
                                      style: TextStyle(
                                        fontSize: isPhone ? 14 : 15,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({required bool isPhone}) {
    final double logoSize = isPhone ? 34 : 42;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isPhone ? 16 : 40,
        vertical: isPhone ? 12 : 20,
      ),
      child: Row(
        children: [
          Container(
            width: logoSize,
            height: logoSize,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo1.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tabaco City Slaughterhouse',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: isPhone ? 15 : 18,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
