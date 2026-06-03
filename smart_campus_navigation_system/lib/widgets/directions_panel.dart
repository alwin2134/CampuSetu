import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/route_result.dart';
import '../theme.dart';

class DirectionsPanel extends StatefulWidget {
  final RouteResult route;
  final String destinationName;
  final String? originName;
  final VoidCallback onCancel;
  final ValueChanged<double>? onSizeChanged;

  const DirectionsPanel({
    super.key,
    required this.route,
    required this.destinationName,
    this.originName,
    required this.onCancel,
    this.onSizeChanged,
  });

  @override
  State<DirectionsPanel> createState() => _DirectionsPanelState();
}

class _DirectionsPanelState extends State<DirectionsPanel> {
  final DraggableScrollableController _controller = DraggableScrollableController();
  bool _isExpanded = false;

  static const double _minSize = 0.25;
  static const double _midSize = 0.42;
  static const double _maxSize = 0.90;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.onSizeChanged != null) {
        widget.onSizeChanged!(_midSize);
      }
    });
    _controller.addListener(() {
      if (widget.onSizeChanged != null) {
        widget.onSizeChanged!(_controller.size);
      }
      final expanded = _controller.size > 0.55;
      if (expanded != _isExpanded) setState(() => _isExpanded = expanded);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snapTo(double size) {
    _controller.animateTo(size,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: _midSize,
      minChildSize: _minSize,
      maxChildSize: _maxSize,
      snap: true,
      snapSizes: const [_minSize, _midSize, _maxSize],
      builder: (context, scrollController) {
        return DirectionsFeedPanel(
          scrollController: scrollController,
          isDraggableSheet: true,
          isExpanded: _isExpanded,
          onHeaderTap: () => _snapTo(_isExpanded ? _midSize : _maxSize),
          route: widget.route,
          destinationName: widget.destinationName,
          originName: widget.originName,
          onCancel: widget.onCancel,
        );
      },
    );
  }
}

class DirectionsFeedPanel extends StatelessWidget {
  final ScrollController? scrollController;
  final bool isDraggableSheet;
  final bool isExpanded;
  final VoidCallback? onHeaderTap;

  final RouteResult route;
  final String destinationName;
  final String? originName;
  final VoidCallback onCancel;

  const DirectionsFeedPanel({
    super.key,
    this.scrollController,
    this.isDraggableSheet = false,
    this.isExpanded = false,
    this.onHeaderTap,
    required this.route,
    required this.destinationName,
    this.originName,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: isDraggableSheet
            ? const BorderRadius.vertical(top: Radius.circular(24))
            : BorderRadius.zero,
        boxShadow: isDraggableSheet ? [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.15),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ] : null,
      ),
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          // ── Drag handle ────────────────────────────────────────────────
          if (isDraggableSheet)
            SliverToBoxAdapter(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onHeaderTap,
                child: _DirectionHeader(
                  route: route,
                  destinationName: destinationName,
                  originName: originName,
                  isExpanded: isExpanded,
                  onCancel: onCancel,
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.only(top: 24),
                child: _DirectionHeader(
                  route: route,
                  destinationName: destinationName,
                  originName: originName,
                  isExpanded: true,
                  onCancel: onCancel,
                ),
              ),
            ),

          // ── Steps list ─────────────────────────────────────────────────
          // Section label
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 4, height: 16,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${route.steps.length} Steps',
                          style: const TextStyle(
                            color: AppTheme.ink700,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Step cards
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _StepTile(
                      step: route.steps[i],
                      index: i,
                      isLast: i == route.steps.length - 1,
                    ),
                    childCount: route.steps.length,
                  ),
                ),

                // Bottom padding
                SliverToBoxAdapter(
                  child: SizedBox(height: MediaQuery.of(context).padding.bottom + 32),
                ),
              ],
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────
class _DirectionHeader extends StatelessWidget {
  final RouteResult route;
  final String destinationName;
  final String? originName;
  final bool isExpanded;
  final VoidCallback onCancel;

  const _DirectionHeader({
    required this.route,
    required this.destinationName,
    this.originName,
    required this.isExpanded,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppTheme.ink300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // Route summary card
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.shadowPrimary,
          ),
          child: Column(
            children: [
              // Origin → Destination
              Row(
                children: [
                  // Origin dot
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primary, width: 2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      originName ?? 'Your Location',
                      style: const TextStyle(
                        color: AppTheme.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 3, bottom: 3),
                child: Row(
                  children: [
                    Container(
                      width: 2, height: 14,
                      color: AppTheme.white.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.place_rounded, color: AppTheme.white, size: 12),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      destinationName,
                      style: const TextStyle(
                        color: AppTheme.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ETA + Distance + Cancel row
              Row(
                children: [
                  // ETA chip
                  _InfoChip(
                    icon: Icons.access_time_rounded,
                    text: route.durationLabel,
                  ),
                  const SizedBox(width: 8),
                  // Distance chip
                  _InfoChip(
                    icon: Icons.straighten_rounded,
                    text: route.distanceLabel,
                  ),
                  // Walking chip
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.directions_walk_rounded,
                    text: 'Walking',
                  ),
                  const Spacer(),
                  // Cancel
                  GestureDetector(
                    onTap: onCancel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppTheme.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, color: AppTheme.white, size: 15),
                          SizedBox(width: 5),
                          Text(
                            'End',
                            style: TextStyle(
                              color: AppTheme.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Divider(height: 1, color: AppTheme.ink300.withValues(alpha: 0.5)),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.white, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AppTheme.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step tile ──────────────────────────────────────────────────────────────
class _StepTile extends StatelessWidget {
  final RouteStep step;
  final int index;
  final bool isLast;

  const _StepTile({required this.step, required this.index, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline column
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isLast
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : AppTheme.ink100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      step.icon,
                      size: 18,
                      color: isLast ? AppTheme.primary : AppTheme.ink700,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: AppTheme.ink300.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Instruction + distance
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.instruction,
                      style: TextStyle(
                        color: isLast ? AppTheme.primary : AppTheme.ink900,
                        fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                    if (step.distanceLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        step.distanceLabel,
                        style: const TextStyle(
                          color: AppTheme.ink500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate()
      .slideX(begin: 0.08, end: 0, delay: Duration(milliseconds: index * 40), duration: 300.ms, curve: Curves.easeOutCubic)
      .fadeIn(delay: Duration(milliseconds: index * 40), duration: 250.ms);
  }
}
