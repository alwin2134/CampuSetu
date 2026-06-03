import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;
import '../models/campus.dart';
import '../models/building.dart';
import '../models/room.dart';
import '../models/event.dart';
import '../models/campus_node.dart';
import '../models/campus_edge.dart';

class SupabaseService {
  // Singleton pattern
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  final _supabase = Supabase.instance.client;

  // --- Campuses ---
  Future<List<Campus>> getCampuses() async {
    final response = await _supabase.from('campuses').select().order('name');
    return (response as List).map((json) => Campus.fromJson(json)).toList();
  }

  // --- Buildings ---
  Future<List<Building>> getBuildings(String campusId) async {
    final response = await _supabase
        .from('buildings')
        .select()
        .eq('campus_id', campusId)
        .order('name');
    return (response as List).map((json) => Building.fromJson(json)).toList();
  }

  Future<List<Building>> getAllBuildings() async {
    final response = await _supabase
        .from('buildings')
        .select()
        .order('name');
    return (response as List).map((json) => Building.fromJson(json)).toList();
  }



  // --- Events ---
  Future<List<Event>> getEvents() async {
    final response = await _supabase
        .from('events')
        .select()
        .order('event_time', ascending: true);
    return (response as List).map((json) => Event.fromJson(json)).toList();
  }

  Future<void> addEvent(String name, String description, double latitude,
      double longitude, {DateTime? eventTime}) async {
    await _supabase.from('events').insert({
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      if (eventTime != null) 'event_time': eventTime.toIso8601String(),
    });
  }

  Future<void> addBuilding(String name, String campusId, double latitude,
      double longitude, {String? description}) async {
    await _supabase.from('buildings').insert({
      'name': name,
      'campus_id': campusId,
      'latitude': latitude,
      'longitude': longitude,
      if (description != null && description.isNotEmpty) 'description': description,
    });
  }

  Future<void> addCampus(String name, double latitude, double longitude,
      {String? description}) async {
    await _supabase.from('campuses').insert({
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      if (description != null && description.isNotEmpty) 'description': description,
    });
  }

  Future<void> deleteEvent(String id) async {
    await _supabase.from('events').delete().eq('id', id);
  }

  Future<void> deleteBuilding(String id) async {
    await _supabase.from('buildings').delete().eq('id', id);
  }

  Future<void> deleteCampus(String id) async {
    await _supabase.from('campuses').delete().eq('id', id);
  }

  // --- Rooms ---
  Future<List<Room>> getRooms() async {
    final response = await _supabase.from('rooms').select().order('name');
    return (response as List).map((json) => Room.fromJson(json)).toList();
  }

  Future<void> addRoom(Room room) async {
    await _supabase.from('rooms').insert(room.toJson());
  }

  Future<void> deleteRoom(String id) async {
    await _supabase.from('rooms').delete().eq('id', id);
  }

  // ── Campus Road Graph ─────────────────────────────────────────────────────

  Future<List<CampusNode>> getCampusNodes({String? campusId}) async {
    var query = _supabase.from('campus_nodes').select();
    if (campusId != null) query = query.eq('campus_id', campusId);
    final response = await query.order('created_at');
    return (response as List).map((j) => CampusNode.fromJson(j)).toList();
  }

  Future<List<CampusEdge>> getCampusEdges() async {
    final response = await _supabase
        .from('campus_edges')
        .select()
        .order('created_at');
    return (response as List).map((j) => CampusEdge.fromJson(j)).toList();
  }

  /// Add a waypoint node and return the saved node (with generated id)
  Future<CampusNode> addCampusNode({
    required double latitude,
    required double longitude,
    String nodeType = 'waypoint',
    String? name,
    String? campusId,
    int floorLevel = 0,
    double? altitude,
  }) async {
    final response = await _supabase
        .from('campus_nodes')
        .insert({
          'latitude':  latitude,
          'longitude': longitude,
          'node_type': nodeType,
          if (name != null && name.isNotEmpty) 'name': name,
          'campus_id': campusId,
          'floor_level': floorLevel,
          'altitude': ?altitude,
        })
        .select()
        .single();
    return CampusNode.fromJson(response);
  }

  /// Connect two nodes with a bi-directional edge pair
  Future<void> addCampusEdge({
    required String sourceNodeId,
    required String targetNodeId,
    required double distanceMetres,
    bool isAccessible = true,
  }) async {
    await _supabase.from('campus_edges').insert([
      {
        'source_node_id': sourceNodeId,
        'target_node_id': targetNodeId,
        'distance_metres': distanceMetres,
        'is_accessible': isAccessible,
      },
      {
        'source_node_id': targetNodeId,
        'target_node_id': sourceNodeId,
        'distance_metres': distanceMetres,
        'is_accessible': isAccessible,
      },
    ]);
  }

  Future<void> deleteCampusNode(String nodeId) async {
    // Edges deleted automatically via ON DELETE CASCADE in DB
    await _supabase.from('campus_nodes').delete().eq('id', nodeId);
  }

  Future<void> deleteCampusEdgesByNodes(
      String sourceNodeId, String targetNodeId) async {
    await _supabase
        .from('campus_edges')
        .delete()
        .or('and(source_node_id.eq.$sourceNodeId,target_node_id.eq.$targetNodeId),'
            'and(source_node_id.eq.$targetNodeId,target_node_id.eq.$sourceNodeId)');
  }

  // ── Haversine distance (metres) ───────────────────────────────────────────
  static double haversineDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}
