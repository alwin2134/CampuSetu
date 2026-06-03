import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/building.dart';
import '../theme.dart';
import '../widgets/shimmer_loading.dart';

class CampusBottomSheet extends StatefulWidget {
  final List<Event> events;
  final List<Building> buildings;
  final bool isLoading;
  final void Function(Event) onEventTap;
  final void Function(Building) onBuildingTap;
  final VoidCallback onRefresh;
  final ValueChanged<double>? onSizeChanged;
  final VoidCallback? onNavigateTap;
  final VoidCallback? onEventsTap;
  final VoidCallback? onBuildingsTap;
  final VoidCallback? onAboutTap;

  const CampusBottomSheet({
    super.key,
    required this.events,
    required this.buildings,
    required this.isLoading,
    required this.onEventTap,
    required this.onBuildingTap,
    required this.onRefresh,
    this.onSizeChanged,
    this.onNavigateTap,
    this.onEventsTap,
    this.onBuildingsTap,
    this.onAboutTap,
  });

  @override
  State<CampusBottomSheet> createState() => CampusBottomSheetState();
}

class CampusBottomSheetState extends State<CampusBottomSheet> {
  final DraggableScrollableController _controller = DraggableScrollableController();
  bool _isExpanded = false;

  double _minSize = 0.12;
  double _midSize = 0.42;
  static const double _maxSize = 0.92;

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
      final expanded = _controller.size > 0.5;
      if (expanded != _isExpanded) setState(() => _isExpanded = expanded);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void snapTo(double size) {
    if (_controller.isAttached) {
      _controller.animateTo(
        size,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    // Dynamically calculate sizes to ensure the top peek is always reachable on small screens
    _minSize = math.max(0.12, 100 / screenHeight);
    _midSize = math.max(0.42, 350 / screenHeight);

    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: _midSize,
      minChildSize: _minSize,
      maxChildSize: _maxSize,
      snap: true,
      snapSizes: [_minSize, _midSize, _maxSize],
      builder: (context, scrollController) {
        return CampusFeedPanel(
          scrollController: scrollController,
          isDraggableSheet: true,
          isExpanded: _isExpanded,
          onHeaderTap: () => snapTo(_isExpanded ? _midSize : _maxSize),
          events: widget.events,
          buildings: widget.buildings,
          isLoading: widget.isLoading,
          onEventTap: widget.onEventTap,
          onBuildingTap: widget.onBuildingTap,
          onRefresh: widget.onRefresh,
          onNavigateTap: widget.onNavigateTap,
          onEventsTap: () {
            widget.onEventsTap?.call();
            if (_controller.size < _midSize) snapTo(_midSize);
          },
          onBuildingsTap: () {
            widget.onBuildingsTap?.call();
            if (_controller.size < _midSize) snapTo(_midSize);
          },
          onAboutTap: widget.onAboutTap,
        );
      },
    );
  }
}

class CampusFeedPanel extends StatefulWidget {
  final ScrollController? scrollController;
  final bool isDraggableSheet;
  final bool isExpanded;
  final VoidCallback? onHeaderTap;

  final List<Event> events;
  final List<Building> buildings;
  final bool isLoading;
  final void Function(Event) onEventTap;
  final void Function(Building) onBuildingTap;
  final VoidCallback onRefresh;
  final VoidCallback? onNavigateTap;
  final VoidCallback? onEventsTap;
  final VoidCallback? onBuildingsTap;
  final VoidCallback? onAboutTap;

  const CampusFeedPanel({
    super.key,
    this.scrollController,
    this.isDraggableSheet = false,
    this.isExpanded = false,
    this.onHeaderTap,
    required this.events,
    required this.buildings,
    required this.isLoading,
    required this.onEventTap,
    required this.onBuildingTap,
    required this.onRefresh,
    this.onNavigateTap,
    this.onEventsTap,
    this.onBuildingsTap,
    this.onAboutTap,
  });

  @override
  State<CampusFeedPanel> createState() => _CampusFeedPanelState();
}

class _CampusFeedPanelState extends State<CampusFeedPanel> {
  String _activeTab = 'events';

  void _showTab(String tab) {
    setState(() => _activeTab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: widget.isDraggableSheet 
          ? const BorderRadius.vertical(top: Radius.circular(32))
          : BorderRadius.zero,
        boxShadow: widget.isDraggableSheet ? [
          BoxShadow(
            color: AppTheme.ink900.withValues(alpha: 0.1),
            blurRadius: 32,
            offset: const Offset(0, -6),
          ),
        ] : null,
      ),
      child: CustomScrollView(
        controller: widget.scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Drag Handle + Header ──────────────────────────────────
          if (widget.isDraggableSheet)
            SliverToBoxAdapter(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onHeaderTap,
                child: _SheetHeader(isExpanded: widget.isExpanded),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                alignment: Alignment.center,
                child: _SheetHeader(isExpanded: true),
              ),
            ),

          // Quick-action row
          SliverToBoxAdapter(
            child: _QuickActions(
              onNavigateTap: widget.onNavigateTap,
              onEventsTap: () {
                _showTab('events');
                widget.onEventsTap?.call();
              },
              onBuildingsTap: () {
                _showTab('buildings');
                widget.onBuildingsTap?.call();
              },
              onAboutTap: widget.onAboutTap,
            ),
          ),

          // Section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 4, height: 18,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _activeTab == 'events' ? 'Recent Events & Happenings' : 'Campus Buildings',
                    style: const TextStyle(
                      color: AppTheme.ink900,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  if (_activeTab == 'events')
                    GestureDetector(
                      onTap: widget.onRefresh,
                      child: const Icon(Icons.refresh_rounded, color: AppTheme.ink500, size: 20),
                    ),
                ],
              ),
            ),
          ),

          // List based on tab
          if (_activeTab == 'events') ...[
            if (widget.isLoading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _EventCardShimmer(),
                  childCount: 4,
                ),
              )
            else if (widget.events.isEmpty)
              SliverToBoxAdapter(child: _EmptyEventsState())
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _EventCard(
                    event: widget.events[index],
                    index: index,
                    onTap: () => widget.onEventTap(widget.events[index]),
                  ),
                  childCount: widget.events.length,
                ),
              ),
          ] else if (_activeTab == 'buildings') ...[
            if (widget.isLoading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _EventCardShimmer(),
                  childCount: 4,
                ),
              )
            else if (widget.buildings.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No buildings found.', style: TextStyle(color: AppTheme.ink500))),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _BuildingCard(
                    building: widget.buildings[index],
                    index: index,
                    onTap: () => widget.onBuildingTap(widget.buildings[index]),
                  ),
                  childCount: widget.buildings.length,
                ),
              ),
          ],

          // Bottom padding (increased to avoid system navigation bar interference)
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.bottom + 72),
          ),
        ],
      ),
    );
  }
}

// ── Sheet Header ───────────────────────────────────────────────────────────
class _SheetHeader extends StatelessWidget {
  final bool isExpanded;
  const _SheetHeader({required this.isExpanded});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 10),
          child: Container(
            width: 48, height: 6,
            decoration: BoxDecoration(
              color: AppTheme.ink300,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        // University branding row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
          child: Row(
            children: [
              // University logo placeholder
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppTheme.shadowPrimary,
                  image: const DecorationImage(
                    image: NetworkImage('https://www.topuniversities.com/sites/default/files/profiles/logos/230729061532am753996GU-Icon-227-200x200.jpg'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Galgotias University',
                      style: TextStyle(
                        color: AppTheme.ink900,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 7, height: 7,
                          decoration: const BoxDecoration(
                            color: AppTheme.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Greater Noida, Uttar Pradesh',
                          style: TextStyle(
                            color: AppTheme.ink500,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: const Icon(Icons.keyboard_arrow_up_rounded, color: AppTheme.ink400, size: 22),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: AppTheme.ink300.withValues(alpha: 0.5)),
      ],
    );
  }
}

// ── Quick Actions Row ──────────────────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  final VoidCallback? onNavigateTap;
  final VoidCallback? onEventsTap;
  final VoidCallback? onBuildingsTap;
  final VoidCallback? onAboutTap;

  const _QuickActions({
    this.onNavigateTap,
    this.onEventsTap,
    this.onBuildingsTap,
    this.onAboutTap,
  });

  static const List<_QuickAction> _list = [
    _QuickAction(icon: Icons.map_rounded, label: 'Navigate', color: AppTheme.primary),
    _QuickAction(icon: Icons.event_rounded, label: 'Events', color: AppTheme.eventColor),
    _QuickAction(icon: Icons.business_rounded, label: 'Buildings', color: AppTheme.buildingColor),
    _QuickAction(icon: Icons.info_rounded, label: 'About', color: AppTheme.campusColor),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(
          _list.length,
          (i) {
            VoidCallback? onTap;
            if (i == 0) onTap = onNavigateTap;
            if (i == 1) onTap = onEventsTap;
            if (i == 2) onTap = onBuildingsTap;
            if (i == 3) onTap = onAboutTap;
            return _QuickActionButton(action: _list[i], index: i, onTap: onTap);
          },
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  const _QuickAction({required this.icon, required this.label, required this.color});
}

class _QuickActionButton extends StatelessWidget {
  final _QuickAction action;
  final int index;
  final VoidCallback? onTap;
  
  const _QuickActionButton({
    required this.action,
    required this.index,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(action.icon, color: action.color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            action.label,
            style: const TextStyle(
              color: AppTheme.ink700,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ).animate()
      .slideY(begin: 0.5, end: 0, delay: Duration(milliseconds: 100 + (index * 50)), duration: 300.ms, curve: Curves.easeOutCubic)
      .fadeIn(delay: Duration(milliseconds: 100 + (index * 50)), duration: 250.ms);
  }
}

class _EventCard extends StatelessWidget {
  final Event event;
  final int index;
  final VoidCallback onTap;

  const _EventCard({required this.event, required this.index, required this.onTap});

  Color get _cardAccent {
    const colors = [
      Color(0xFFF59E0B), Color(0xFF4F46E5), Color(0xFF0D9488),
      Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF0284C7),
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final hasTime = event.eventTime != null;
    final isUpcoming = hasTime && event.eventTime!.isAfter(DateTime.now());

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.ink300.withValues(alpha: 0.5)),
          boxShadow: AppTheme.shadowSm,
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Accent strip
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: _cardAccent,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Category chip
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _cardAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'EVENT',
                              style: TextStyle(
                                color: _cardAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isUpcoming)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'UPCOMING',
                                style: TextStyle(
                                  color: AppTheme.success,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded, color: AppTheme.ink300, size: 18),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        event.name,
                        style: const TextStyle(
                          color: AppTheme.ink900,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (event.description != null && event.description!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          event.description!,
                          style: const TextStyle(
                            color: AppTheme.ink500,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (hasTime) ...[
                            Icon(Icons.access_time_rounded, size: 13, color: _cardAccent),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('MMM d · h:mm a').format(event.eventTime!),
                              style: TextStyle(
                                color: _cardAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          const Icon(Icons.location_on_rounded, size: 13, color: AppTheme.ink400),
                          const SizedBox(width: 3),
                          Text(
                            '${event.latitude.toStringAsFixed(3)}, ${event.longitude.toStringAsFixed(3)}',
                            style: const TextStyle(
                              color: AppTheme.ink400,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate()
     .slideX(begin: 0.1, end: 0, delay: Duration(milliseconds: index * 60), duration: 350.ms, curve: Curves.easeOutCubic)
     .fadeIn(delay: Duration(milliseconds: index * 60), duration: 280.ms);
  }
}

// ── Shimmer Event Card ─────────────────────────────────────────────────────
class _EventCardShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.ink300.withValues(alpha: 0.4)),
        boxShadow: AppTheme.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ShimmerLoading(width: 50, height: 20, borderRadius: BorderRadius.circular(6)),
            const SizedBox(width: 8),
            ShimmerLoading(width: 70, height: 20, borderRadius: BorderRadius.circular(6)),
          ]),
          const SizedBox(height: 10),
          ShimmerLoading(width: double.infinity, height: 16, borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 6),
          ShimmerLoading(width: 200, height: 13, borderRadius: BorderRadius.circular(6)),
          const SizedBox(height: 10),
          ShimmerLoading(width: 150, height: 12, borderRadius: BorderRadius.circular(6)),
        ],
      ),
    );
  }
}

// ── Empty State ────────────────────────────────────────────────────────────
class _EmptyEventsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_busy_rounded, color: AppTheme.primary, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'No events yet',
            style: TextStyle(color: AppTheme.ink900, fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Events added by admins will\nappear here in real time.',
            style: TextStyle(color: AppTheme.ink500, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BuildingCard extends StatelessWidget {
  final Building building;
  final int index;
  final VoidCallback onTap;

  const _BuildingCard({required this.building, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.ink300.withValues(alpha: 0.5)),
          boxShadow: AppTheme.shadowSm,
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Accent strip
              Container(
                width: 5,
                decoration: const BoxDecoration(
                  color: AppTheme.buildingColor,
                  borderRadius: BorderRadius.horizontal(left: Radius.circular(18)),
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.buildingColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'BUILDING',
                              style: TextStyle(
                                color: AppTheme.buildingColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.chevron_right_rounded, color: AppTheme.ink300, size: 18),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        building.name,
                        style: const TextStyle(
                          color: AppTheme.ink900,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (building.description != null && building.description!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          building.description!,
                          style: const TextStyle(
                            color: AppTheme.ink500,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
        .slideY(begin: 0.5, end: 0, delay: Duration(milliseconds: 100 + (index * 50)), duration: 300.ms, curve: Curves.easeOutCubic)
        .fadeIn(delay: Duration(milliseconds: 100 + (index * 50)), duration: 250.ms),
    );
  }
}
