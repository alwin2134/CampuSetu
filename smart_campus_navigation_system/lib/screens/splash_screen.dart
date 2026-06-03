import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToHome();
  }

  Future<void> _navigateToHome() async {
    // Wait for 2.5 seconds to show the splash animation
    await Future.delayed(const Duration(milliseconds: 2500));
    
    if (!mounted) return;
    
    // Navigate to HomeScreen and replace the splash screen in the navigation stack
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 800),
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo Image
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.shadowPrimary,
                image: const DecorationImage(
                  image: AssetImage('assets/images/logo.png'),
                  fit: BoxFit.contain,
                ),
              ),
            ).animate()
              .scale(delay: 200.ms, duration: 600.ms, curve: Curves.easeOutBack)
              .fadeIn(delay: 200.ms, duration: 600.ms),
            
            const SizedBox(height: 24),
            
            // App Title
            const Text(
              'CampuSetu',
              style: TextStyle(
                color: AppTheme.primary,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ).animate()
              .slideY(begin: 0.5, end: 0, delay: 500.ms, duration: 500.ms, curve: Curves.easeOutCubic)
              .fadeIn(delay: 500.ms, duration: 500.ms),
              
            const SizedBox(height: 8),
            
            // Subtitle
            const Text(
              'Smart Campus Navigation',
              style: TextStyle(
                color: AppTheme.ink500,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ).animate()
              .slideY(begin: 0.5, end: 0, delay: 700.ms, duration: 500.ms, curve: Curves.easeOutCubic)
              .fadeIn(delay: 700.ms, duration: 500.ms),
          ],
        ),
      ),
    );
  }
}
