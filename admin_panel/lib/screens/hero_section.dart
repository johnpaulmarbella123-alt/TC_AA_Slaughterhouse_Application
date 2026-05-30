import 'package:flutter/material.dart';
import '../theme.dart';

class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image (Placeholder Gradient)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1B5E20), // Dark Green
                  Color(0xFF2E7D32), // Medium Green
                ],
              ),
            ),
          ),
          // Dark Overlay
          Container(
            color: Colors.black.withOpacity(0.5),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            child: Column(
              children: [
                // Top Header (Logo and Title)
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.location_city, color: AppColors.forestGreen),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Tabaco City Slaughterhouse',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Main Content
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Tabaco City Slaughterhouse: Safe, clean, and quality livestock processing for all community "AA"',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Government-regulated, hygienic, and high-quality meat production providing the best standards for our community.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 40),
                      // Buttons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: () => Navigator.pushNamed(context, '/signup'),
                            child: const Text('Sign Up'),
                          ),
                          const SizedBox(width: 20),
                          OutlinedButton(
                            onPressed: () => Navigator.pushNamed(context, '/login'),
                            child: const Text('Log In'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
