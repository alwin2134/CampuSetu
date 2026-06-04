import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../models/event.dart';
import '../models/room.dart';
import '../models/building.dart';
import '../models/route_result.dart';
import '../models/campus_node.dart';
import '../models/campus_edge.dart';
import '../services/supabase_service.dart';
import '../services/routing_service.dart';
import '../services/update_service.dart';
import 'package:ota_update/ota_update.dart';
import '../theme.dart';
import 'admin_map_screen.dart';
import '../widgets/event_details_sheet.dart';
import '../widgets/app_marker.dart';
import '../widgets/campus_bottom_sheet.dart';
import '../widgets/directions_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final MapController _mapController = MapController();
  final SearchController _searchController = SearchController();

  List<Event> _events = [];
  List<Room> _rooms = [];
  List<Building> _buildings = [];
  List<CampusNode> _nodes = [];
  List<CampusEdge> _edges = [];
  bool _isLoading = true;
  Event? _selectedEvent;

  // Default campus location
  final LatLng _defaultCenter = const LatLng(28.3669, 77.5413);

  // Geolocation
  LatLng? _currentLocation;
  StreamSubscription<Position>? _positionStream;
  bool _locationDenied = false;

  // Compass
  bool _isCompassMode = false;
  double _compassHeading = 0.0;
  bool _hardwareCompassActive = false;
  StreamSubscription<CompassEvent>? _compassSubscription;

  // Directions
  RouteResult? _routeResult;
  LatLng? _routeDestination;
  String? _routeDestinationName;
  bool _isRouting = false;
  bool _isLoadingRoute = false;
  bool _isPickingOrigin = false; // user must tap map to set start
  bool _destinationReached = false;
  String _destinationDirection = '';

  // Quick-filter
  String _activeFilter = 'All';
  final List<String> _filters = ['All', 'Events', 'Buildings'];

  // Bottom Sheet
  double _sheetSize = 0.42;
  final GlobalKey<CampusBottomSheetState> _bottomSheetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadData();
    _initLocation();
    _checkForUpdates(false);
    
    // Listen to device compass for map rotation
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (!mounted || event.heading == null) return;
      _hardwareCompassActive = true;
      
      setState(() => _compassHeading = event.heading!);
      if (_isCompassMode && _currentLocation != null) {
        // Keep the map centered on the user while rotating
        _mapController.move(_currentLocation!, _mapController.camera.zoom);
        _mapController.rotate(360 - _compassHeading);
      }
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _compassSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── Geolocation ───────────────────────────────────────────────────────────
  Future<void> _initLocation() async {
    try {
      // Check if location service is available
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services disabled');
        return;
      }

      // Request permission (triggers browser popup on web)
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationDenied = true);
        return;
      }

      // ── Get an immediate one-shot fix first (works on web) ──────────────
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            timeLimit: Duration(seconds: 10),
          ),
        );
        if (mounted && !pos.latitude.isNaN && !pos.longitude.isNaN) {
          setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
        }
      } catch (e) {
        debugPrint('Initial position error: $e');
      }

      // ── Then stream live updates ─────────────────────────────────────────
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0, // Continuous updates (no distance threshold)
        ),
      ).listen(
        (pos) {
          if (mounted && !pos.latitude.isNaN && !pos.longitude.isNaN) {
            setState(() {
              _currentLocation = LatLng(pos.latitude, pos.longitude);
              
              // Fallback: If hardware compass fails, use GPS bearing when moving
              if (pos.heading > 0 && pos.speed > 0.3) {
                // Continuously update if hardware compass hasn't fired yet
                if (!_hardwareCompassActive) {
                  _compassHeading = pos.heading;
                  if (_isCompassMode && _currentLocation != null) {
                    _mapController.move(_currentLocation!, _mapController.camera.zoom);
                    _mapController.rotate(360 - _compassHeading);
                  }
                }
              } else if (_isCompassMode && _currentLocation != null) {
                // Even if we don't have a new heading, keep the camera centered on the user!
                _mapController.move(_currentLocation!, _mapController.camera.zoom);
              }
              
              // Check proximity to destination if routing
              if (_isRouting && _routeDestination != null) {
                final dist = Geolocator.distanceBetween(
                  pos.latitude, pos.longitude,
                  _routeDestination!.latitude, _routeDestination!.longitude,
                );
                
                if (dist <= 10.0) {
                  if (!_destinationReached) {
                    final bearing = Geolocator.bearingBetween(
                      pos.latitude, pos.longitude,
                      _routeDestination!.latitude, _routeDestination!.longitude,
                    );
                    
                    double relBearing = (bearing - pos.heading) % 360;
                    if (relBearing < 0) relBearing += 360;
                    
                    String dir = 'straight ahead';
                    if (relBearing > 10 && relBearing < 170) {
                      dir = 'on your right';
                    } else if (relBearing > 190 && relBearing < 350) {
                      dir = 'on your left';
                    }
                    
                    _destinationReached = true;
                    _destinationDirection = dir;
                  }
                } else if (_destinationReached) {
                  _destinationReached = false;
                }
              }
            });
          }
        },
        onError: (e) => debugPrint('Location stream error: $e'),
      );
    } catch (e) {
      debugPrint('Location init error: $e');
    }
  }

  // ── Data ──────────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      final events = await _supabaseService.getEvents();
      final rooms = await _supabaseService.getRooms();
      final buildings = await _supabaseService.getAllBuildings();
      final nodes = await _supabaseService.getCampusNodes();
      final edges = await _supabaseService.getCampusEdges();
      if (mounted) {
        setState(() {
          _events = events;
          _rooms = rooms;
          _buildings = buildings;
          _nodes = nodes;
          _edges = edges;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Error loading data: $e");
    }
  }

  // ── Auto-Updater ────────────────────────────────────────────────
  Future<void> _checkForUpdates(bool manualCheck) async {
    if (manualCheck) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            SizedBox(width: 2),
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Checking for updates…'),
          ]),
          backgroundColor: AppTheme.ink800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    final updateInfo = await UpdateService.checkForUpdate();

    if (!mounted) return;

    if (updateInfo.hasUpdate && updateInfo.downloadUrl != null) {
      _showUpdateDialog(updateInfo);
    } else if (manualCheck) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('You’re on the latest version!'),
          ]),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _showUpdateDialog(UpdateInfo updateInfo) {
    final notes = (updateInfo.releaseNotes ?? '').trim();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.ink300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Icon + title row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.shadowPrimary,
                  ),
                  child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Update Available',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.ink900)),
                      const SizedBox(height: 3),
                      Text(updateInfo.versionName ?? '',
                        style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),

            if (notes.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text("What's new",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.ink700)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    notes,
                    style: const TextStyle(color: AppTheme.ink600, fontSize: 13, height: 1.5),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Vibration.vibrate(duration: 50);
                      Navigator.pop(ctx);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.ink300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Later', style: TextStyle(color: AppTheme.ink600, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Vibration.vibrate(duration: 50);
                      if (defaultTargetPlatform == TargetPlatform.android) {
                        if (!await Permission.requestInstallPackages.isGranted) {
                          await Permission.requestInstallPackages.request();
                        }
                      }
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      _startUpdateDownload(updateInfo.downloadUrl!);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download Now', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _startUpdateDownload(String url) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StreamBuilder<OtaEvent>(
          stream: UpdateService.downloadAndInstallUpdate(url),
          builder: (context, snapshot) {
            String statusTitle = 'Preparing…';
            String statusSub = 'Getting ready to download';
            double? progress;
            bool isError = false;
            bool isDone = false;

            if (snapshot.hasError) {
              isError = true;
              statusTitle = 'Update Failed';
              statusSub = snapshot.error.toString();
            } else if (snapshot.hasData) {
              final event = snapshot.data!;
              final statusName = event.status.name.toUpperCase();
              if (statusName == 'DOWNLOADING') {
                final pct = double.tryParse(event.value ?? '0') ?? 0;
                progress = pct / 100;
                statusTitle = 'Downloading Update';
                statusSub = '${pct.toStringAsFixed(0)}% complete';
              } else if (statusName == 'INSTALLING') {
                progress = 1.0;
                statusTitle = 'Installing…';
                statusSub = 'Almost there! Follow the on-screen prompt.';
                isDone = true;
              } else {
                statusTitle = 'Status: ${event.status.name}';
                statusSub = event.value ?? '';
              }
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).padding.bottom + 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: AppTheme.ink300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Animated icon
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isError
                        ? AppTheme.danger.withValues(alpha: 0.1)
                        : isDone
                          ? AppTheme.success.withValues(alpha: 0.1)
                          : AppTheme.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isError ? Icons.error_outline_rounded
                        : isDone ? Icons.check_circle_rounded
                        : Icons.download_rounded,
                      color: isError ? AppTheme.danger
                        : isDone ? AppTheme.success
                        : AppTheme.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(statusTitle,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppTheme.ink900)),
                  const SizedBox(height: 6),
                  Text(statusSub,
                    style: const TextStyle(color: AppTheme.ink500, fontSize: 13),
                    textAlign: TextAlign.center),

                  const SizedBox(height: 24),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: AppTheme.ink200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isError ? AppTheme.danger : AppTheme.primary,
                      ),
                    ),
                  ),

                  if (isError || isDone) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (isError)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Vibration.vibrate(duration: 50);
                                Navigator.pop(ctx);
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppTheme.danger),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text('Close', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        if (isError) const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () async {
                              Vibration.vibrate(duration: 50);
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                            child: const Text('Download in Browser', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }


  String get _mapTilerUrl {
    final apiKey = dotenv.env['MAPTILER_API_KEY'] ?? '';
    return 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$apiKey';
  }

  // ── Directions ────────────────────────────────────────────────────────────
  Future<void> _getDirectionsTo(LatLng dest, String name) async {
    setState(() {
      _routeDestination    = dest;
      _routeDestinationName = name;
    });

    if (_currentLocation == null) {
      // No GPS — let the user tap to pick origin
      setState(() => _isPickingOrigin = true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.touch_app_rounded, color: Colors.white, size: 17),
          SizedBox(width: 10),
          Expanded(child: Text('Tap the map to set your starting point')),
        ]),
        backgroundColor: AppTheme.ink900,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 6),
      ));
      return;
    }

    await _fetchRoute(_currentLocation!, dest);
  }

  Future<void> _fetchRoute(LatLng from, LatLng to) async {
    setState(() => _isLoadingRoute = true);
    try {
      final result = _nodes.isNotEmpty && _edges.isNotEmpty
          ? RoutingService().fetchLocalRoute(from, to, _nodes, _edges)
          : await RoutingService().fetchRoute(from, to);
          
      if (!mounted) return;
      setState(() {
        _routeResult     = result;
        _isRouting       = true;
        _isLoadingRoute  = false;
        _isPickingOrigin = false;
      });
      // Fit map to show the full route
      _fitRouteBounds(result.polyline);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingRoute = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 17),
          const SizedBox(width: 10),
          Expanded(child: Text('Could not get directions: $e')),
        ]),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  void _fitRouteBounds(List<LatLng> points) {
    if (points.isEmpty) return;
    
    final validPoints = points.where((p) => !p.latitude.isNaN && !p.longitude.isNaN).toList();
    if (validPoints.isEmpty) return;

    final bounds = LatLngBounds.fromPoints(validPoints);
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.only(
            top: 100.0,
            left: 50.0,
            right: 50.0,
            bottom: MediaQuery.of(context).size.height * 0.45,
          ),
        ),
      );
    } catch (e) {
      // Fallback if fitCamera fails
      _mapController.move(bounds.center, 15.5);
    }
  }

  void _cancelDirections() {
    setState(() {
      _routeResult         = null;
      _routeDestination    = null;
      _routeDestinationName = null;
      _isRouting           = false;
      _isLoadingRoute      = false;
      _isPickingOrigin     = false;
      _destinationReached  = false;
      _destinationDirection = '';
    });
  }
  // ── Event detail sheets ──────────────────────────────────────────
  void _showEventDetails(Event event) {
    setState(() => _selectedEvent = event);
    _mapController.move(LatLng(event.latitude, event.longitude), 16.5);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EventDetailsSheet(
        event: event,
        onDirectionsTap: () {
          Navigator.pop(context);
          _getDirectionsTo(LatLng(event.latitude, event.longitude), event.name);
        },
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _selectedEvent = null);
    });
  }

  // ── UI helpers ────────────────────────────────────────────────────────────
  PageRoute _fadeRoute(Widget page) => PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(opacity: animation, child: child),
    transitionDuration: const Duration(milliseconds: 300),
  );



  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 800;
          if (isDesktop) {
            return _buildDesktopLayout(constraints);
          }
          return _buildMobileLayout(constraints);
        },
      ),
    );
  }

  Widget _buildDesktopLayout(BoxConstraints constraints) {
    final topPad = MediaQuery.of(context).padding.top;
    return Row(
      children: [
        // Left Panel
        SizedBox(
          width: 380,
          child: _isRouting && _routeResult != null
            ? DirectionsFeedPanel(
                route: _routeResult!,
                destinationName: _routeDestinationName ?? 'Destination',
                originName: null,
                isExpanded: true,
                isDraggableSheet: false,
                onCancel: _cancelDirections,
              )
            : CampusFeedPanel(
                events: _events,
                buildings: _buildings,
                isLoading: _isLoading,
                isDraggableSheet: false,
                isExpanded: true,
                onEventTap: _showEventDetails,
                onBuildingTap: (building) {
                  _mapController.move(LatLng(building.latitude, building.longitude), 18);
                },
                onRefresh: _loadData,
                onNavigateTap: () {
                  _searchController.openView();
                },
                onEventsTap: () => setState(() => _activeFilter = 'Events'),
                onBuildingsTap: () => setState(() => _activeFilter = 'All'),
                onAboutTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('CampuSetu'),
                      content: const Text('Built for Galgotias University.\n\nNavigate seamlessly across campus, find events in real time, and map out the easiest paths to your destination.'),
                      actions: [
                        TextButton(onPressed: () {
                          Navigator.pop(ctx);
                          _checkForUpdates(true);
                        }, child: const Text('Check for Updates')),
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                      ],
                    ),
                  );
                },
              ),
        ),
        // Right Map Area
        Expanded(
          child: Stack(
            children: [
              _buildMap(),
              Positioned(
                top: topPad + 12,
                left: 16,
                right: 72,
                child: _buildSearchBar(),
              ),
              Positioned(
                top: topPad + 12,
                right: 16,
                child: _buildAdminButton(),
              ),
              Positioned(
                top: topPad + 76,
                left: 16,
                right: 16,
                child: _buildFilterChips(),
              ),
              Positioned(
                bottom: 32,
                right: 16,
                child: _buildFABs(),
              ),
              if (_isLoading) _buildLoadingOverlay(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BoxConstraints constraints) {
    final topPad = MediaQuery.of(context).padding.top;
    final screenHeight = constraints.maxHeight;
    
    // Dynamic offsets for small screens
    final searchTopOffset = topPad + (screenHeight < 700 ? 8 : 12);
    final filterTopOffset = searchTopOffset + (screenHeight < 700 ? 54 : 64);

    double fabOpacity = 1.0;
    if (_sheetSize > 0.45) {
      fabOpacity = (1.0 - ((_sheetSize - 0.45) / 0.15)).clamp(0.0, 1.0);
    }
    
    return Stack(
        children: [
          // ── Full-Screen Map ─────────────────────────────────────
          _buildMap(),

          // ── Search Bar ──────────────────────────────────────────
          Positioned(
            top: searchTopOffset,
            left: 16,
            right: 72, // leave room for admin FAB
            child: _buildSearchBar(),
          ),

          // ── Top-Right Admin Button ───────────────────────────────
          Positioned(
            top: searchTopOffset,
            right: 16,
            child: _buildAdminButton(),
          ),

          // ── Filter chips ────────────────────────────────────────
          Positioned(
            top: filterTopOffset,
            left: 0,
            right: 0,
            child: _buildFilterChips(),
          ),

          // ── Bottom FABs ─────────────────────────────────────────
          Positioned(
            bottom: 32 + (_sheetSize * MediaQuery.of(context).size.height),
            right: 16,
            child: IgnorePointer(
              ignoring: fabOpacity == 0.0,
              child: Opacity(
                opacity: fabOpacity,
                child: _buildFABs(),
              ),
            ),
          ),

          // ── Location denied banner ──────────────────────────────
          if (_locationDenied)
            Positioned(
              bottom: 110 + (_sheetSize * MediaQuery.of(context).size.height),
              left: 16,
              right: 72,
              child: IgnorePointer(
                ignoring: fabOpacity == 0.0,
                child: Opacity(
                  opacity: fabOpacity,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _locationDenied = false);
                      _initLocation();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.ink900.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: AppTheme.shadowMd,
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.location_off_rounded, color: AppTheme.warning, size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Location denied — tap to allow',
                              style: TextStyle(color: AppTheme.white, fontWeight: FontWeight.w500, fontSize: 13),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: AppTheme.ink300, size: 18),
                        ],
                      ),
                    ),
                  ).animate().slideY(begin: 1, end: 0, duration: 350.ms, curve: Curves.easeOutCubic),
                ),
              ),
            ),

          // ── Route loading spinner ──────────────────────────────────
          if (_isLoadingRoute)
            Positioned.fill(
              child: Container(
                color: AppTheme.ink900.withValues(alpha: 0.25),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    decoration: BoxDecoration(
                      color: AppTheme.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: AppTheme.shadowLg,
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 3, color: AppTheme.primary),
                        SizedBox(height: 14),
                        Text('Finding route…',
                          style: TextStyle(color: AppTheme.ink700, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Origin-pick hint banner ────────────────────────────────
          if (_isPickingOrigin)
            Positioned(
              top: topPad + 130,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.ink900.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Row(children: [
                  const Icon(Icons.touch_app_rounded, color: AppTheme.warning, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Tap the map to set your start', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
                  GestureDetector(
                    onTap: _cancelDirections,
                    child: const Icon(Icons.close_rounded, color: AppTheme.ink300, size: 18),
                  ),
                ]),
              ).animate().slideY(begin: -0.3, end: 0, duration: 350.ms, curve: Curves.easeOutCubic),
            ),

          // ── Destination reached banner ─────────────────────────────
          if (_destinationReached)
            Positioned(
              top: topPad + 130,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppTheme.shadowMd,
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Destination Reached!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        Text('Your destination is $_destinationDirection.', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w500, fontSize: 13)),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelDirections,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ]),
              ).animate().slideY(begin: -0.3, end: 0, duration: 400.ms, curve: Curves.easeOutBack),
            ),

          // ── Loading overlay ─────────────────────────────────────
          if (_isLoading) _buildLoadingOverlay(),

          // ── Bottom sheet: directions when routing, campus feed otherwise ──
          if (_isRouting && _routeResult != null)
            Positioned.fill(
              child: DirectionsPanel(
                route: _routeResult!,
                destinationName: _routeDestinationName ?? 'Destination',
                onCancel: _cancelDirections,
                onSizeChanged: (size) {
                  if (mounted) setState(() => _sheetSize = size);
                },
              ),
            )
          else
            Positioned.fill(
              child: CampusBottomSheet(
                key: _bottomSheetKey,
                events: _events,
                buildings: _buildings,
                isLoading: _isLoading,
                onEventTap: _showEventDetails,
                onBuildingTap: (building) {
                  // Focus the map on the building
                  _mapController.move(LatLng(building.latitude, building.longitude), 18);
                  // Collapse the sheet so they can see the map
                  _bottomSheetKey.currentState?.snapTo(0.12);
                },
                onRefresh: _loadData,
                onSizeChanged: (size) {
                  if (mounted) setState(() => _sheetSize = size);
                },
                onNavigateTap: () {
                  _searchController.openView();
                },
                onEventsTap: () {
                  setState(() => _activeFilter = 'Events');
                  if (_sheetSize < 0.2) {
                    _bottomSheetKey.currentState?.snapTo(0.42);
                  }
                },
                onBuildingsTap: () {
                  setState(() => _activeFilter = 'All');
                  if (_sheetSize < 0.2) {
                    _bottomSheetKey.currentState?.snapTo(0.42);
                  }
                },
                onAboutTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('CampuSetu'),
                      content: const Text('Built for Galgotias University.\n\nNavigate seamlessly across campus, find events in real time, and map out the easiest paths to your destination.'),
                      actions: [
                        TextButton(onPressed: () {
                          Navigator.pop(ctx);
                          _checkForUpdates(true);
                        }, child: const Text('Check for Updates')),
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      );
  }

  // ── Map ───────────────────────────────────────────────────────────────────
  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _defaultCenter,
        initialZoom: 14.5,
        onPositionChanged: (position, hasGesture) {
          // If the user manually drags or zooms the map, turn off Compass auto-follow mode!
          if (hasGesture && _isCompassMode) {
            setState(() => _isCompassMode = false);
            _mapController.rotate(0); // Snap back to North when free-roaming
          }
        },
        onTap: (tapPosition, latLng) {
          if (_searchController.isOpen) _searchController.closeView('');
          // Origin-pick mode: use tapped point as route start
          if (_isPickingOrigin && _routeDestination != null) {
            _fetchRoute(latLng, _routeDestination!);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _mapTilerUrl,
          userAgentPackageName: 'com.example.smart_campus_navigation_system',
        ),
        // Route polyline
        if (_routeResult != null)
          PolylineLayer(
            polylines: [
              // Shadow polyline
              Polyline(
                points: _routeResult!.polyline,
                color: AppTheme.accent.withValues(alpha: 0.3),
                strokeWidth: 14,
              ),
              // Main polyline
              Polyline(
                points: _routeResult!.polyline,
                color: AppTheme.accent,
                strokeWidth: 6,
              ),
            ],
          ),
        // All place markers
        MarkerLayer(markers: _buildMarkers()),
      ],
    ).animate().fadeIn(duration: 900.ms);
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Event markers
    if (_activeFilter == 'All' || _activeFilter == 'Events') {
      for (int i = 0; i < _events.length; i++) {
        final e = _events[i];
        final isSelected = _selectedEvent?.id == e.id;
        markers.add(Marker(
          point: LatLng(e.latitude, e.longitude),
          width: 46,
          height: 56,
          child: AppMarker(
            icon: Icons.event_rounded,
            color: AppTheme.eventColor,
            isSelected: isSelected,
            onTap: () => _showEventDetails(e),
            animationDelay: i * 60,
          ),
        ));
      }
    }

    // Building markers
    if (_activeFilter == 'All' || _activeFilter == 'Buildings') {
      int bIndex = 0;
      for (final b in _buildings) {
        markers.add(Marker(
          point: LatLng(b.latitude, b.longitude),
          width: 44,
          height: 54,
          child: AppMarker(
            icon: Icons.business_rounded,
            color: AppTheme.primary,
            onTap: () => _getDirectionsTo(LatLng(b.latitude, b.longitude), b.name),
            animationDelay: bIndex * 50,
          ),
        ));
        bIndex++;
      }
    }

    // Room markers
    if (_activeFilter == 'All' || _activeFilter == 'Rooms') {
      int rIndex = 0;
      for (final r in _rooms) {
        markers.add(Marker(
          point: r.location,
          width: 40,
          height: 50,
          child: AppMarker(
            icon: Icons.meeting_room_rounded,
            color: AppTheme.primary,
            onTap: () => _getDirectionsTo(r.location, r.name),
            animationDelay: rIndex * 50,
          ),
        ));
        rIndex++;
      }
    }

    // Blue dot (current location) with compass direction
    if (_currentLocation != null) {
      // Calculate rotation so that the arrow always points North if map isn't rotated,
      // or points in the direction of the phone relative to the screen.
      // The Marker widget keeps itself upright by default unless rotate: true is set.
      // We will rotate the inner container to point toward the compass heading.
      final radians = _compassHeading * (math.pi / 180);
      
      markers.add(Marker(
        point: _currentLocation!,
        width: 36,
        height: 36,
        child: Transform.rotate(
          angle: radians,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow and dot
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ).animate(onPlay: (c) => c.repeat())
               .scale(begin: const Offset(1, 1), end: const Offset(1.15, 1.15), duration: 1200.ms)
               .then().scale(begin: const Offset(1.15, 1.15), end: const Offset(1, 1), duration: 1200.ms),
               
              // Directional arrow pointing UP
              Positioned(
                top: 0,
                child: Icon(Icons.keyboard_arrow_up_rounded, color: const Color(0xFF2563EB), size: 18),
              ),
            ],
          ),
        ),
      ));
    }

    return markers;
  }

  // ── Search ────────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppTheme.shadowMd,
      ),
      child: SearchAnchor.bar(
        searchController: _searchController,
        barHintText: 'Search campus, events, buildings…',
        barElevation: WidgetStateProperty.all(0),
        barBackgroundColor: WidgetStateProperty.all(Colors.transparent),
        barShape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        ),
        suggestionsBuilder: (context, controller) {
          final q = controller.text.toLowerCase();
          final List<Widget> items = [];

          final roomHits = _rooms.where((r) => r.name.toLowerCase().contains(q));
          final eventHits = _events.where((e) => e.name.toLowerCase().contains(q));
          final buildingHits = _buildings.where((b) => b.name.toLowerCase().contains(q));

          if (buildingHits.isNotEmpty) {
            items.add(_searchSectionHeader('Buildings'));
            for (var b in buildingHits) {
              items.add(_searchTile(
                icon: Icons.business_rounded,
                color: AppTheme.primary,
                title: b.name,
                subtitle: 'Building',
                onTap: () {
                  controller.closeView('');
                  _getDirectionsTo(LatLng(b.latitude, b.longitude), b.name);
                },
              ));
            }
          }

          if (roomHits.isNotEmpty) {
            items.add(_searchSectionHeader('Rooms'));
            for (var r in roomHits) {
              items.add(_searchTile(
                icon: Icons.meeting_room_rounded,
                color: AppTheme.primary,
                title: r.name,
                subtitle: 'Room',
                onTap: () {
                  controller.closeView('');
                  _getDirectionsTo(r.location, r.name);
                },
              ));
            }
          }

          if (eventHits.isNotEmpty) {
            items.add(_searchSectionHeader('Events'));
            for (var e in eventHits) {
              items.add(_searchTile(
                icon: Icons.event_rounded,
                color: AppTheme.eventColor,
                title: e.name,
                subtitle: 'Event',
                onTap: () { controller.closeView(''); _showEventDetails(e); },
              ));
            }
          }

          if (items.isEmpty) {
            items.add(const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.search_off_rounded, color: AppTheme.ink300, size: 40),
                  SizedBox(height: 8),
                  Text('No results found', style: TextStyle(color: AppTheme.ink500)),
                ],
              ),
            ));
          }
          return items;
        },
      ),
    ).animate()
      .slideY(begin: -0.5, end: 0, duration: 500.ms, curve: Curves.easeOutCubic)
      .fadeIn(duration: 400.ms);
  }

  Widget _searchSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.ink500,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _searchTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: () {
        Vibration.vibrate(duration: 50);
        onTap();
      },
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.ink500)),
      trailing: const Icon(Icons.north_west_rounded, size: 16, color: AppTheme.ink300),
    );
  }

  // ── Admin button ──────────────────────────────────────────────────────────
  Widget _buildAdminButton() {
    return Material(
      color: AppTheme.white,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () async {
          Vibration.vibrate(duration: 50);
          await Navigator.push(context, _fadeRoute(const AdminMapScreen()));
          _loadData();
        },
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: AppTheme.shadowMd,
            color: AppTheme.white,
          ),
          child: const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primary, size: 24),
        ),
      ),
    ).animate()
     .scale(delay: 300.ms, duration: 400.ms, curve: Curves.easeOutBack);
  }

  // ── Filter Chips ──────────────────────────────────────────────────────────
  Widget _buildFilterChips() {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final filter = _filters[i];
          final active = _activeFilter == filter;
          return GestureDetector(
            onTap: () {
              Vibration.vibrate(duration: 50);
              setState(() => _activeFilter = filter);
              if (_sheetSize < 0.1) {
                _bottomSheetKey.currentState?.snapTo(0.42);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppTheme.primary : AppTheme.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: active ? AppTheme.shadowPrimary : AppTheme.shadowSm,
              ),
              child: Text(
                filter,
                style: TextStyle(
                  color: active ? AppTheme.white : AppTheme.ink700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    ).animate()
     .slideY(begin: -0.4, end: 0, delay: 200.ms, duration: 450.ms, curve: Curves.easeOutCubic)
     .fadeIn(delay: 200.ms, duration: 350.ms);
  }

  // ── FABs ──────────────────────────────────────────────────────────────────
  Widget _buildFABs() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // My Location / Compass Toggle
        _MiniFAB(
          icon: _locationDenied 
              ? Icons.location_off_rounded 
              : (_isCompassMode ? Icons.explore_rounded : Icons.my_location_rounded),
          onTap: () {
            if (_locationDenied) {
              // Re-trigger permission request
              setState(() => _locationDenied = false);
              _initLocation();
            } else if (_currentLocation != null) {
              if (_isRouting && _routeResult != null) {
                // User requested to see the full route again when pressing the button during routing
                setState(() => _isCompassMode = false);
                _mapController.rotate(0);
                _fitRouteBounds(_routeResult!.polyline);
              } else {
                setState(() {
                  _isCompassMode = !_isCompassMode;
                  if (!_isCompassMode) {
                    _mapController.rotate(0); // Reset rotation to North when disabled
                  }
                });
                _mapController.move(_currentLocation!, 16.5);
              }
            } else {
              // No location yet — try again
              _initLocation();
              _mapController.move(_defaultCenter, 15.0);
            }
          },
        ).animate().scale(delay: 500.ms, duration: 400.ms, curve: Curves.easeOutBack),

        const SizedBox(height: 12),

        // Zoom in
        _MiniFAB(
          icon: Icons.add_rounded,
          onTap: () {
            final zoom = _mapController.camera.zoom;
            _mapController.move(_mapController.camera.center, zoom + 1);
          },
        ).animate().scale(delay: 550.ms, duration: 400.ms, curve: Curves.easeOutBack),

        const SizedBox(height: 12),

        // Zoom out
        _MiniFAB(
          icon: Icons.remove_rounded,
          onTap: () {
            final zoom = _mapController.camera.zoom;
            _mapController.move(_mapController.camera.center, zoom - 1);
          },
        ).animate().scale(delay: 600.ms, duration: 400.ms, curve: Curves.easeOutBack),
      ],
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: AppTheme.white.withValues(alpha: 0.6),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                strokeWidth: 2.5,
              ),
              SizedBox(height: 16),
              Text(
                'Loading campus data…',
                style: TextStyle(
                  color: AppTheme.ink700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mini FAB helper ────────────────────────────────────────────────────────
class _MiniFAB extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _MiniFAB({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          Vibration.vibrate(duration: 50);
          if (onTap != null) onTap!();
        },
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: AppTheme.shadowMd,
            color: AppTheme.white,
          ),
          child: Icon(icon, color: AppTheme.ink700, size: 22),
        ),
      ),
    );
  }
}
