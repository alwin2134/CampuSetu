import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import '../models/campus.dart';
import '../models/building.dart';
import '../models/room.dart';
import '../models/campus_node.dart';
import '../models/campus_edge.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/app_marker.dart';

// ── Admin modes ───────────────────────────────────────────────────────────
enum AdminMode { map, place, recordPath, delete }

// ── Category model ─────────────────────────────────────────────────────────
enum PlaceCategory { event, building, room }

extension PlaceCategoryExt on PlaceCategory {
  String get label {
    switch (this) {
      case PlaceCategory.event:    return 'Event';
      case PlaceCategory.building: return 'Building';
      case PlaceCategory.room:     return 'Room';
    }
  }
  IconData get icon {
    switch (this) {
      case PlaceCategory.event:    return Icons.event_rounded;
      case PlaceCategory.building: return Icons.business_rounded;
      case PlaceCategory.room:     return Icons.meeting_room_rounded;
    }
  }
  Color get color {
    switch (this) {
      case PlaceCategory.event:    return AppTheme.eventColor;
      case PlaceCategory.building: return AppTheme.buildingColor;
      case PlaceCategory.room:     return AppTheme.primary;
    }
  }
  LinearGradient get gradient {
    switch (this) {
      case PlaceCategory.event:    return AppTheme.eventGradient;
      case PlaceCategory.building: return AppTheme.buildingGradient;
      case PlaceCategory.room:     return AppTheme.primaryGradient;
    }
  }
}

// ── AdminMapScreen ─────────────────────────────────────────────────────────
class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final MapController _mapController = MapController();

  final LatLng _defaultCenter = const LatLng(28.3669, 77.5413);
  LatLng? _currentLocation;
  StreamSubscription<Position>? _positionStream;

  // Placed items shown on map
  final List<_PlacedItem> _placedItems = [];
  bool _isLocating = false;

  // Loaded data for dropdowns
  List<Campus> _campuses = [];
  List<Building> _buildings = [];

  // ── Road drawing state ────────────────────────────────────────────────────
  AdminMode _adminMode = AdminMode.map;
  List<CampusNode> _roadNodes = [];
  List<CampusEdge> _roadEdges = [];
  CampusNode? _lastRecordedNode;
  final int _selectedFloor = 0; // For indoor mapping

  String get _mapTilerUrl {
    final apiKey = dotenv.env['MAPTILER_API_KEY'] ?? '';
    return 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$apiKey';
  }

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadData();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // ── Location ───────────────────────────────────────────────────────────────
  Future<void> _initLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return;
    }
    if (perm == LocationPermission.deniedForever) return;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((pos) {
      if (mounted) setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
    });
  }

  Future<Position> _fetchCurrentPosition() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location service disabled');

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) throw Exception('Location permission denied');
      }
      if (perm == LocationPermission.deniedForever) throw Exception('Location permission permanently denied');

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation),
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // ── Data ───────────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      final campuses = await _supabaseService.getCampuses();
      final events = await _supabaseService.getEvents();
      final buildings = await _supabaseService.getAllBuildings();
      final rooms = await _supabaseService.getRooms();
      
      final items = <_PlacedItem>[];
      for (final b in buildings) {
        items.add(_PlacedItem(id: b.id, location: LatLng(b.latitude, b.longitude), category: PlaceCategory.building, name: b.name));
      }
      for (final e in events) {
        items.add(_PlacedItem(id: e.id, location: LatLng(e.latitude, e.longitude), category: PlaceCategory.event, name: e.name));
      }
      for (final r in rooms) {
        items.add(_PlacedItem(id: r.id, location: r.location, category: PlaceCategory.room, name: r.name));
      }

      if (mounted) {
        setState(() {
          _campuses = campuses;
          _buildings = buildings;
          _placedItems.clear();
          _placedItems.addAll(items);
        });
      }
    } catch (e) {
      debugPrint('Error loading admin data: $e');
    }
    _loadRoadGraph();
  }

  Future<void> _loadRoadGraph() async {
    try {
      final nodes = await _supabaseService.getCampusNodes();
      final edges = await _supabaseService.getCampusEdges();
      if (mounted) {
        setState(() {
          _roadNodes = nodes;
          _roadEdges = edges;
        });
      }
    } catch (e) {
      debugPrint('Road graph load error: $e');
    }
  }

  Future<void> _fetchLocationAndDo(Future<void> Function(LatLng, double?) action) async {
    setState(() => _isLocating = true);
    LatLng location;
    double? altitude;
    try {
      final pos = await _fetchCurrentPosition();
      location = LatLng(pos.latitude, pos.longitude);
      altitude = pos.altitude;
    } catch (e) {
      location = _currentLocation ?? _defaultCenter;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.location_off_rounded, color: AppTheme.white, size: 17),
          SizedBox(width: 10),
          Text('GPS unavailable, using map center'),
        ]),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }

    if (!mounted) return;
    _mapController.move(location, 17.0);
    await action(location, altitude);
  }

  void _onMapTap(LatLng point) {
    if (_isLocating) return;
    if (_adminMode == AdminMode.recordPath) {
      _recordPathNode(point, null);
    } else if (_adminMode == AdminMode.place) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _AddPlaceSheet(
          fetchedLocation: point,
          fetchedAltitude: null,
          campuses: _campuses,
          buildings: _buildings,
          activeFloor: _selectedFloor,
          onRefetchLocation: () async {
            try { 
              final pos = await _fetchCurrentPosition();
              return LatLng(pos.latitude, pos.longitude);
            } catch (_) { return point; }
          },
          onSave: (item) async {
            await _saveItem(item);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      );
    }
  }

  Future<void> _onDropNode() async {
    await _fetchLocationAndDo((loc, alt) => _recordPathNode(loc, alt));
  }

  Future<void> _onAddPlace() async {
    await _fetchLocationAndDo((loc, alt) async {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _AddPlaceSheet(
          fetchedLocation: loc,
          fetchedAltitude: alt,
          campuses: _campuses,
          buildings: _buildings,
          activeFloor: _selectedFloor,
          onRefetchLocation: () async {
            try { 
              final pos = await _fetchCurrentPosition();
              return LatLng(pos.latitude, pos.longitude);
            } catch (_) { return loc; }
          },
          onSave: (item) async {
            await _saveItem(item);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      );
    });
  }

  Future<void> _recordPathNode(LatLng point, double? altitude) async {
    try {
      final node = await _supabaseService.addCampusNode(
        latitude: point.latitude, 
        longitude: point.longitude,
        floorLevel: _selectedFloor,
        altitude: altitude,
      );
      
      double dist = 0;
      bool edgeAdded = false;
      if (_lastRecordedNode != null) {
        dist = SupabaseService.haversineDistance(
          _lastRecordedNode!.latitude, _lastRecordedNode!.longitude, 
          node.latitude, node.longitude
        );
        await _supabaseService.addCampusEdge(
          sourceNodeId: _lastRecordedNode!.id,
          targetNodeId: node.id,
          distanceMetres: dist,
        );
        edgeAdded = true;
      }
      
      setState(() {
        _roadNodes.add(node);
        _lastRecordedNode = node;
      });

      if (edgeAdded) {
        _loadRoadGraph(); // Reload to get the new edges
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.location_on_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(edgeAdded ? 'Dropped & Linked (${dist.round()}m)' : 'Dropped start node'),
        ]),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _saveItem(_AddPlaceData data) async {
    try {
      switch (data.category) {
        case PlaceCategory.event:
          await _supabaseService.addEvent(
            data.name, data.description ?? '',
            data.location.latitude, data.location.longitude,
            eventTime: data.eventTime,
          );
        case PlaceCategory.building:
          if (data.campusId == null) throw Exception('Please select a campus');
          await _supabaseService.addBuilding(
            data.name, data.campusId!,
            data.location.latitude, data.location.longitude,
            description: data.description,
          );

        case PlaceCategory.room:
          if (data.buildingId == null) throw Exception('Please select a building');
          await _supabaseService.addRoom(Room(
            id: '',
            buildingId: data.buildingId!,
            name: data.name,
            roomType: 'classroom',
            floorLevel: data.floorLevel ?? 0,
            location: data.location,
            altitude: data.altitude,
          ));
      }
      await _loadData();
      if (!mounted) return;
      _mapController.move(data.location, 17.0);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: AppTheme.white, size: 18),
          const SizedBox(width: 10),
          Text('"${data.name}" added!', style: const TextStyle(fontWeight: FontWeight.w500)),
        ]),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  // ── Handlers ───────────────────────────────────────────────────────────────

  /// Called when a node marker is tapped in map mode
  Future<void> _onNodeTapRecordPath(CampusNode node) async {
    if (_lastRecordedNode?.id == node.id) {
      setState(() => _lastRecordedNode = null); // Deselect
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Path broken. Next drop will start a new path.'),
        backgroundColor: AppTheme.ink700,
        behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    setState(() => _lastRecordedNode = node);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Node selected. Next drop will connect to this.'),
      backgroundColor: AppTheme.primary,
      behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  /// Called when a node is tapped in delete mode
  Future<void> _onNodeTapDelete(CampusNode node) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Waypoint?'),
        content: const Text('This will also remove all road segments connected to this waypoint.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _supabaseService.deleteCampusNode(node.id);
      await _loadRoadGraph();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  /// Called when a place is tapped in delete mode
  Future<void> _onPlaceTapDelete(_PlacedItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete ${item.category.label}?'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      if (item.category == PlaceCategory.event) await _supabaseService.deleteEvent(item.id);
      if (item.category == PlaceCategory.building) await _supabaseService.deleteBuilding(item.id);

      if (item.category == PlaceCategory.room) await _supabaseService.deleteRoom(item.id);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final headerH = topPad + 70.0;
    return Scaffold(
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 17.0,
              onTap: (tapPos, point) => _onMapTap(point),
            ),
            children: [
              TileLayer(
                urlTemplate: _mapTilerUrl,
                userAgentPackageName: 'com.example.smart_campus_navigation_system',
              ),
              // Road edges as polylines
              if (_roadEdges.isNotEmpty) _buildRoadPolylines(),
              // Markers (nodes + places + blue dot)
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),

          // ── Header ───────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 16),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                boxShadow: AppTheme.shadowLg,
              ),
              child: Row(
                children: [
                  _HeaderIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Admin Panel',
                          style: TextStyle(color: AppTheme.white, fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(
                          _adminMode == AdminMode.place      ? 'Tap map or press + to add a place' :
                          _adminMode == AdminMode.recordPath ? 'Tap map or walk & press + to map roads' :
                          'Tap a waypoint to delete it',
                          style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  _CountBadge(count: _roadNodes.length, label: 'nodes'),
                ],
              ),
            ).animate().slideY(begin: -1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
          ),

          // ── Mode toolbar ─────────────────────────────────────────
          Positioned(
            top: headerH + 8,
            left: 0, right: 0,
            child: Column(
              children: [
                _ModeToolbar(
                  current: _adminMode,
                  onSelect: (mode) => setState(() {
                    _adminMode = mode;
                    _lastRecordedNode = null;
                  }),
                ),

              ],
            ),
          ),

          // ── Bottom hint ───────────────────────────────────────────
          if (_roadNodes.isEmpty && _adminMode == AdminMode.recordPath)
            Positioned(
              bottom: 120 + MediaQuery.of(context).padding.bottom,
              left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.ink900.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_walk_rounded, color: AppTheme.white, size: 16),
                      SizedBox(width: 8),
                      Text('Tap map or walk & press + to map roads',
                        style: TextStyle(color: AppTheme.white, fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ).animate().slideY(begin: 1, end: 0, delay: 300.ms, duration: 400.ms, curve: Curves.easeOutCubic),
              ),
            ),

          // ── Action Buttons ────────────────────────────────────────
          if (_adminMode == AdminMode.place || _adminMode == AdminMode.recordPath || _adminMode == AdminMode.map)
            Positioned(
              bottom: 40 + MediaQuery.of(context).padding.bottom,
              right: 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLocating)
                    const Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  if (_adminMode == AdminMode.place || _adminMode == AdminMode.map)
                    FloatingActionButton(
                      heroTag: 'add_place',
                      onPressed: _isLocating ? null : _onAddPlace,
                      backgroundColor: AppTheme.white,
                      foregroundColor: AppTheme.primary,
                      tooltip: 'Add Place',
                      child: const Icon(Icons.add_location_alt_rounded),
                    ).animate().scale(delay: 300.ms),
                  if (_adminMode == AdminMode.map) const SizedBox(width: 12),
                  if (_adminMode == AdminMode.recordPath || _adminMode == AdminMode.map)
                    FloatingActionButton(
                      heroTag: 'drop_node',
                      onPressed: _isLocating ? null : _onDropNode,
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.white,
                      tooltip: 'Drop Node',
                      child: const Icon(Icons.route_rounded),
                    ).animate().scale(delay: 400.ms),
                ],
              ),
            ),
        ],
      ),
    );
  }

  PolylineLayer _buildRoadPolylines() {
    // Build a map of nodeId -> node for quick lookup
    final nodeMap = {for (final n in _roadNodes) n.id: n};
    // Deduplicate: only draw each pair once (source < target lexicographically)
    final seen = <String>{};
    final polylines = <Polyline>[];

    for (final edge in _roadEdges) {
      final key = [edge.sourceNodeId, edge.targetNodeId]..sort();
      final keyStr = key.join('|');
      if (seen.contains(keyStr)) continue;
      seen.add(keyStr);

      final src = nodeMap[edge.sourceNodeId];
      final tgt = nodeMap[edge.targetNodeId];
      if (src == null || tgt == null) continue;

      polylines.add(Polyline(
        points: [LatLng(src.latitude, src.longitude), LatLng(tgt.latitude, tgt.longitude)],
        color: const Color(0xFF22C55E),
        strokeWidth: 3.5,
      ));
    }

    return PolylineLayer(polylines: polylines);
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Road waypoint nodes
    for (final node in _roadNodes) {
      final isSelected = _lastRecordedNode?.id == node.id;
      markers.add(Marker(
        point: LatLng(node.latitude, node.longitude),
        width: 28, height: 28,
        child: GestureDetector(
          onTap: () {
            if (_adminMode == AdminMode.recordPath) _onNodeTapRecordPath(node);
            if (_adminMode == AdminMode.delete)     _onNodeTapDelete(node);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.warning : const Color(0xFF22C55E),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppTheme.white : const Color(0xFF16A34A),
                width: isSelected ? 3 : 2,
              ),
              boxShadow: [BoxShadow(
                color: (isSelected ? AppTheme.warning : const Color(0xFF22C55E)).withValues(alpha: 0.5),
                blurRadius: isSelected ? 10 : 6,
                spreadRadius: 1,
              )],
            ),
          ),
        ),
      ));
    }

    // Place markers (events, buildings, campus)
    for (int i = 0; i < _placedItems.length; i++) {
      final item = _placedItems[i];
      markers.add(Marker(
        point: item.location,
        width: 46, height: 56,
        child: GestureDetector(
          onTap: () {
            if (_adminMode == AdminMode.delete) _onPlaceTapDelete(item);
          },
          child: AppMarker(
            icon: item.category.icon,
            color: item.category.color,
            animationDelay: i * 60,
          ),
        ),
      ));
    }

    // Blue dot — current location
    if (_currentLocation != null) {
      markers.add(Marker(
        point: _currentLocation!,
        width: 22, height: 22,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.white, width: 3),
            boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 2)],
          ),
        ).animate(onPlay: (c) => c.repeat())
         .scale(begin: const Offset(1, 1), end: const Offset(1.18, 1.18), duration: 1200.ms)
         .then().scale(begin: const Offset(1.18, 1.18), end: const Offset(1, 1), duration: 1200.ms),
      ));
    }

    return markers;
  }
}

// ── Add Place Sheet ────────────────────────────────────────────────────────
class _AddPlaceData {
  final PlaceCategory category;
  final String name;
  final String? description;
  final LatLng location;
  final double? altitude;
  final DateTime? eventTime;
  final String? campusId;
  final String? buildingId;
  final int? floorLevel;

  _AddPlaceData({
    required this.category,
    required this.name,
    this.description,
    required this.location,
    this.altitude,
    this.eventTime,
    this.campusId,
    this.buildingId,
    this.floorLevel,
  });
}

class _AddPlaceSheet extends StatefulWidget {
  final LatLng fetchedLocation;
  final double? fetchedAltitude;
  final List<Campus> campuses;
  final List<Building> buildings;
  final int activeFloor;
  final Future<LatLng> Function() onRefetchLocation;
  final Future<void> Function(_AddPlaceData) onSave;

  const _AddPlaceSheet({
    required this.fetchedLocation,
    this.fetchedAltitude,
    required this.campuses,
    required this.buildings,
    required this.activeFloor,
    required this.onRefetchLocation,
    required this.onSave,
  });

  @override
  State<_AddPlaceSheet> createState() => _AddPlaceSheetState();
}

class _AddPlaceSheetState extends State<_AddPlaceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  PlaceCategory _category = PlaceCategory.room;
  late LatLng _location;
  double? _altitude;
  bool _isRefetching = false;
  bool _isSaving = false;
  DateTime? _eventTime;
  String? _selectedCampusId;
  String? _selectedBuildingId;
  late int _selectedFloor;

  @override
  void initState() {
    super.initState();
    _location = widget.fetchedLocation;
    _altitude = widget.fetchedAltitude;
    _selectedFloor = widget.activeFloor;
    _selectedCampusId = widget.campuses.isNotEmpty ? widget.campuses.first.id : null;
    _selectedBuildingId = widget.buildings.isNotEmpty ? widget.buildings.first.id : null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _refetchLocation() async {
    setState(() => _isRefetching = true);
    try {
      final loc = await widget.onRefetchLocation();
      setState(() => _location = loc);
    } finally {
      if (mounted) setState(() => _isRefetching = false);
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() {
      _eventTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave(_AddPlaceData(
        category: _category,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
        location: _location,
        altitude: _altitude,
        eventTime: _category == PlaceCategory.event ? _eventTime : null,
        campusId: _category == PlaceCategory.building ? _selectedCampusId : null,
        buildingId: _category == PlaceCategory.room ? _selectedBuildingId : null,
        floorLevel: _category == PlaceCategory.room ? _selectedFloor : null,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppTheme.danger));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: AppTheme.ink300, borderRadius: BorderRadius.circular(2)),
                ),
              ),

              // ── Gradient Header ──────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: _category.gradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_category.icon, color: AppTheme.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Add New Place',
                            style: TextStyle(color: AppTheme.white, fontWeight: FontWeight.w700, fontSize: 17)),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.my_location_rounded, color: AppTheme.white, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                '${_location.latitude.toStringAsFixed(5)}, ${_location.longitude.toStringAsFixed(5)}',
                                style: TextStyle(color: AppTheme.white.withValues(alpha: 0.88), fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Re-fetch GPS button
                    GestureDetector(
                      onTap: _isRefetching ? null : _refetchLocation,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _isRefetching
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.white))
                          : const Icon(Icons.gps_fixed_rounded, color: AppTheme.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Category Selector ────────────────────────────────
                      const Text('Category', style: TextStyle(color: AppTheme.ink500, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                      const SizedBox(height: 10),
                      Row(
                        children: PlaceCategory.values.map((cat) {
                          final active = _category == cat;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _category = cat),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: active ? cat.color : AppTheme.ink100,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: active ? [BoxShadow(color: cat.color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] : [],
                                ),
                                child: Column(
                                  children: [
                                    Icon(cat.icon, color: active ? AppTheme.white : AppTheme.ink500, size: 20),
                                    const SizedBox(height: 4),
                                    Text(cat.label,
                                      style: TextStyle(
                                        color: active ? AppTheme.white : AppTheme.ink500,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                      )),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),

                      // ── Name ─────────────────────────────────────────────
                      TextFormField(
                        controller: _nameCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: '${_category.label} Name *',
                          hintText: _nameHint,
                          prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),

                      // ── Description ───────────────────────────────────────
                      TextFormField(
                        controller: _descCtrl,
                        maxLines: 3,
                        minLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                          hintText: 'Add more details…',
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Event-specific: Date & Time ───────────────────────
                      if (_category == PlaceCategory.event) ...[
                        GestureDetector(
                          onTap: _pickDateTime,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppTheme.ink100,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month_rounded, color: _eventTime != null ? AppTheme.eventColor : AppTheme.ink500, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  _eventTime != null
                                    ? '${_eventTime!.day}/${_eventTime!.month}/${_eventTime!.year}  ${_eventTime!.hour.toString().padLeft(2,'0')}:${_eventTime!.minute.toString().padLeft(2,'0')}'
                                    : 'Set date & time (optional)',
                                  style: TextStyle(
                                    color: _eventTime != null ? AppTheme.ink900 : AppTheme.ink500,
                                    fontWeight: _eventTime != null ? FontWeight.w500 : FontWeight.normal,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(Icons.chevron_right_rounded, color: AppTheme.ink300, size: 18),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // ── Building-specific: Campus selector ────────────────
                      if (_category == PlaceCategory.building && widget.campuses.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _selectedCampusId,
                          decoration: const InputDecoration(
                            labelText: 'Parent Campus *',
                            prefixIcon: Icon(Icons.account_balance_rounded),
                          ),
                          items: widget.campuses.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() => _selectedCampusId = v),
                          validator: (v) => v == null ? 'Please select a campus' : null,
                        ),
                        const SizedBox(height: 14),
                      ],

                      // ── Room-specific: Building and Floor ────────────────
                      if (_category == PlaceCategory.room && widget.buildings.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _selectedBuildingId,
                          decoration: const InputDecoration(
                            labelText: 'Parent Building *',
                            prefixIcon: Icon(Icons.business_rounded),
                          ),
                          items: widget.buildings.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (v) => setState(() => _selectedBuildingId = v),
                          validator: (v) => v == null ? 'Please select a building' : null,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedFloor,
                          decoration: const InputDecoration(
                            labelText: 'Floor Level *',
                            prefixIcon: Icon(Icons.layers_rounded),
                          ),
                          items: List.generate(26, (i) {
                            final f = i - 5;
                            final label = f == 0 ? 'Ground Floor (0)' : f < 0 ? 'Basement ($f)' : 'Floor $f';
                            return DropdownMenuItem(value: f, child: Text(label));
                          }),
                          onChanged: (v) => setState(() => _selectedFloor = v ?? 0),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // ── Save Button ───────────────────────────────────────
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: _category.gradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(color: _category.color.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 5))],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: AppTheme.white,
                              disabledBackgroundColor: Colors.transparent,
                              disabledForegroundColor: AppTheme.white.withValues(alpha: 0.6),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: _isSaving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.white))
                              : Icon(_category.icon),
                            label: Text(
                              _isSaving ? 'Saving…' : 'Add ${_category.label} to Map',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ).animate()
        .slideY(begin: 0.25, end: 0, duration: 350.ms, curve: Curves.easeOutCubic)
        .fadeIn(duration: 250.ms);
  }

  String get _nameHint {
    switch (_category) {
      case PlaceCategory.event:    return 'e.g. Science Fair 2026';
      case PlaceCategory.building: return 'e.g. Engineering Block A';
      case PlaceCategory.room:     return 'e.g. Room 101';
    }
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────

class _PlacedItem {
  final String id;
  final LatLng location;
  final PlaceCategory category;
  final String name;
  _PlacedItem({required this.id, required this.location, required this.category, required this.name});
}


class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.white, size: 20),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final String label;
  const _CountBadge({required this.count, this.label = 'placed'});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.layers_rounded, color: AppTheme.white, size: 14),
          const SizedBox(width: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: Text(
              '$count $label',
              key: ValueKey('$count$label'),
              style: const TextStyle(color: AppTheme.white, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mode Toolbar ───────────────────────────────────────────────────────────────
class _ModeToolbar extends StatelessWidget {
  final AdminMode current;
  final void Function(AdminMode) onSelect;

  const _ModeToolbar({required this.current, required this.onSelect});

  static const _modes = [
    (AdminMode.place,      Icons.add_location_alt_rounded, 'Places'),
    (AdminMode.recordPath, Icons.directions_walk_rounded,  'Map Roads'),
    (AdminMode.delete,     Icons.delete_outline_rounded,   'Delete'),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppTheme.shadowMd,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _modes.map((m) {
            final (mode, icon, label) = m;
            final active = current == mode;
            final color = mode == AdminMode.delete ? AppTheme.danger : AppTheme.primary;
            return GestureDetector(
              onTap: () => onSelect(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: active
                    ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
                    : [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                      size: 20,
                      color: active ? AppTheme.white : AppTheme.ink500,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: active ? AppTheme.white : AppTheme.ink500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ).animate().slideY(begin: -0.3, end: 0, delay: 300.ms, duration: 350.ms, curve: Curves.easeOutCubic)
       .fadeIn(delay: 300.ms, duration: 280.ms),
    );
  }
}
