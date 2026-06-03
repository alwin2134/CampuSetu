import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';

/// A reusable, animated map marker that pops into view.
class AppMarker extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;
  final int animationDelay;

  const AppMarker({
    super.key,
    required this.icon,
    required this.color,
    this.isSelected = false,
    this.onTap,
    this.animationDelay = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: isSelected ? 1.2 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppTheme.white : AppTheme.white.withValues(alpha: 0.9),
                  width: isSelected ? 3 : 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: isSelected ? 16 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: AppTheme.white, size: 20),
            ),
            // Pointer tip
            Container(
              width: 2,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(2)),
              ),
            ),
          ],
        ),
      ),
    ).animate().scale(
          delay: Duration(milliseconds: animationDelay),
          duration: 450.ms,
          curve: Curves.easeOutBack,
        );
  }
}
