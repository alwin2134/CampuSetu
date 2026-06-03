import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/route_result.dart';
import '../models/campus_node.dart';
import '../models/campus_edge.dart';

// Priority Queue for Dijkstra
class _PqEntry implements Comparable<_PqEntry> {
  final String nodeId;
  final double distance;
  _PqEntry(this.nodeId, this.distance);

  @override
  int compareTo(_PqEntry other) => distance.compareTo(other.distance);
}

class RoutingService {
  // Singleton
  static final RoutingService _instance = RoutingService._internal();
  factory RoutingService() => _instance;
  RoutingService._internal();

  static const String _baseUrl = 'https://router.project-osrm.org/route/v1/walking';
  static const Duration _timeout = Duration(seconds: 12);

  /// Computes a local route using Dijkstra's algorithm over CampusNodes and CampusEdges.
  RouteResult fetchLocalRoute(
    LatLng from,
    LatLng to,
    List<CampusNode> nodes,
    List<CampusEdge> edges,
  ) {
    if (nodes.isEmpty) throw Exception('No mapping data available on campus.');

    // Build adjacency list from explicitly drawn edges (bidirectional)
    final adj = <String, List<CampusEdge>>{};
    for (final e in edges) {
      if (!e.isAccessible) continue;
      adj.putIfAbsent(e.sourceNodeId, () => []).add(e);
      adj.putIfAbsent(e.targetNodeId, () => []).add(
        CampusEdge(
          id: '${e.id}_rev',
          sourceNodeId: e.targetNodeId,
          targetNodeId: e.sourceNodeId,
          distanceMetres: e.distanceMetres,
          isAccessible: e.isAccessible,
          createdAt: e.createdAt,
        )
      );
    }

    // Mathematical Auto-Routing: Auto-connect nodes
    for (int i = 0; i < nodes.length; i++) {
      final n1 = nodes[i];
      final neighbors = <MapEntry<CampusNode, double>>[];
      
      for (int j = 0; j < nodes.length; j++) {
        if (i == j) continue;
        final n2 = nodes[j];
        final dist = _haversineDistance(n1.latitude, n1.longitude, n2.latitude, n2.longitude);
        
        if (n1.floorLevel == n2.floorLevel) {
          if (dist < 80.0) neighbors.add(MapEntry(n2, dist)); // Max 80m jump on same floor
        } else {
          if (dist < 15.0) neighbors.add(MapEntry(n2, dist + 15.0)); // Stacked stairs/elevators (adds 15m penalty)
        }
      }
      
      // Connect to the 4 mathematically closest neighbors
      neighbors.sort((a, b) => a.value.compareTo(b.value));
      final closest = neighbors.take(4);
      
      for (final neighbor in closest) {
        final n2 = neighbor.key;
        final dist = neighbor.value;
        adj.putIfAbsent(n1.id, () => []).add(
          CampusEdge(
            id: 'auto_${n1.id}_${n2.id}',
            sourceNodeId: n1.id,
            targetNodeId: n2.id,
            distanceMetres: dist,
            isAccessible: true,
            createdAt: DateTime.now(),
          )
        );
      }
    }

    // Now, _getNearestConnectedNode will see ALL nodes as connected because we auto-generated edges!
    final startNode = _getNearestConnectedNode(from, nodes, adj);
    final endNode = _getNearestConnectedNode(to, nodes, adj);

    // Dijkstra
    final dist = <String, double>{};
    final prev = <String, String>{};
    for (final n in nodes) {
      dist[n.id] = double.infinity;
    }
    dist[startNode.id] = 0.0;

    final pq = <_PqEntry>[];
    pq.add(_PqEntry(startNode.id, 0.0));

    final nodeMap = {for (final n in nodes) n.id: n};

    while (pq.isNotEmpty) {
      pq.sort();
      final curr = pq.removeAt(0);

      if (curr.nodeId == endNode.id) break;
      if (curr.distance > dist[curr.nodeId]!) continue;

      final neighbors = adj[curr.nodeId] ?? [];
      for (final edge in neighbors) {
        double edgeDist = edge.distanceMetres ?? 0.0;
        if (edgeDist <= 0.0) {
          final sNode = nodeMap[edge.sourceNodeId];
          final tNode = nodeMap[edge.targetNodeId];
          if (sNode != null && tNode != null) {
            edgeDist = _haversineDistance(sNode.latitude, sNode.longitude, tNode.latitude, tNode.longitude);
          } else {
            edgeDist = 1.0;
          }
        }
        
        final newDist = dist[curr.nodeId]! + edgeDist;
        if (newDist < (dist[edge.targetNodeId] ?? double.infinity)) {
          dist[edge.targetNodeId] = newDist;
          prev[edge.targetNodeId] = curr.nodeId;
          pq.add(_PqEntry(edge.targetNodeId, newDist));
        }
      }
    }

    if (dist[endNode.id] == double.infinity) {
      throw Exception('No path found to the destination.');
    }

    // Reconstruct path
    final pathNodeIds = <String>[];
    String? currentId = endNode.id;
    while (currentId != null) {
      pathNodeIds.insert(0, currentId);
      currentId = prev[currentId];
    }

    final pathNodes = pathNodeIds.map((id) => nodeMap[id]!).toList();

    // Build polyline and steps
    final polyline = <LatLng>[from];
    final steps = <RouteStep>[];
    double totalDistance = 0.0;

    for (int i = 0; i < pathNodes.length; i++) {
      final curr = pathNodes[i];
      polyline.add(LatLng(curr.latitude, curr.longitude));

      if (i > 0) {
        final prevNode = pathNodes[i - 1];
        final dist = _haversineDistance(prevNode.latitude, prevNode.longitude, curr.latitude, curr.longitude);
        totalDistance += dist;

        String instruction;
        String maneuverType = 'continue';
        String maneuverMod = '';
        
        if (prevNode.floorLevel != curr.floorLevel) {
          final isUp = curr.floorLevel > prevNode.floorLevel;
          instruction = 'Go ${isUp ? 'up' : 'down'} to Floor ${curr.floorLevel}';
          maneuverType = 'fork';
          maneuverMod = isUp ? 'right' : 'left'; // arbitrary icon
        } else {
          // Calculate turns using bearing if there's a next node
          if (i < pathNodes.length - 1) {
            final nextNode = pathNodes[i + 1];
            final bearing1 = _calculateBearing(prevNode.latitude, prevNode.longitude, curr.latitude, curr.longitude);
            final bearing2 = _calculateBearing(curr.latitude, curr.longitude, nextNode.latitude, nextNode.longitude);
            
            // Difference in angle (-180 to 180)
            double diff = bearing2 - bearing1;
            if (diff > 180) diff -= 360;
            if (diff < -180) diff += 360;

            if (diff > 25 && diff <= 65) {
              instruction = 'Bear right towards ${nextNode.name ?? 'waypoint'}';
              maneuverType = 'turn'; maneuverMod = 'slight right';
            } else if (diff > 65 && diff <= 115) {
              instruction = 'Turn right towards ${nextNode.name ?? 'waypoint'}';
              maneuverType = 'turn'; maneuverMod = 'right';
            } else if (diff > 115) {
              instruction = 'Sharp right towards ${nextNode.name ?? 'waypoint'}';
              maneuverType = 'turn'; maneuverMod = 'sharp right';
            } else if (diff < -25 && diff >= -65) {
              instruction = 'Bear left towards ${nextNode.name ?? 'waypoint'}';
              maneuverType = 'turn'; maneuverMod = 'slight left';
            } else if (diff < -65 && diff >= -115) {
              instruction = 'Turn left towards ${nextNode.name ?? 'waypoint'}';
              maneuverType = 'turn'; maneuverMod = 'left';
            } else if (diff < -115) {
              instruction = 'Sharp left towards ${nextNode.name ?? 'waypoint'}';
              maneuverType = 'turn'; maneuverMod = 'sharp left';
            } else {
              // Only add instruction if it's a named node, otherwise skip spamming "continue"
              if (curr.name != null && curr.name!.isNotEmpty) {
                 instruction = 'Continue past ${curr.name}';
              } else {
                 instruction = 'Continue straight';
              }
            }
          } else {
             instruction = 'Continue towards destination';
          }
        }

        // Avoid adding too many "Continue straight" steps for closely packed nodes
        if (instruction == 'Continue straight' && steps.isNotEmpty && steps.last.instruction == 'Continue straight') {
          // Just accumulate the distance onto the last step
          final last = steps.removeLast();
          steps.add(RouteStep(
            instruction: last.instruction,
            distanceMetres: last.distanceMetres + dist,
            maneuverType: last.maneuverType,
            maneuverModifier: last.maneuverModifier,
          ));
        } else {
          steps.add(RouteStep(
            instruction: instruction,
            distanceMetres: dist,
            maneuverType: maneuverType,
            maneuverModifier: maneuverMod,
          ));
        }
      }
    }
    
    polyline.add(to);
    final lastDist = _haversineDistance(endNode.latitude, endNode.longitude, to.latitude, to.longitude);
    totalDistance += lastDist;
    steps.add(RouteStep(
      instruction: 'Arrive at destination',
      distanceMetres: lastDist,
      maneuverType: 'arrive',
      maneuverModifier: '',
    ));

    return RouteResult(
      polyline: polyline,
      distanceMetres: totalDistance,
      durationSeconds: totalDistance / 1.4, // avg walking speed 1.4 m/s
      steps: steps,
    );
  }

  CampusNode _getNearestConnectedNode(LatLng pt, List<CampusNode> nodes, Map<String, List<CampusEdge>> adj) {
    CampusNode? best;
    double bestDist = double.infinity;
    for (final n in nodes) {
      // Ignore nodes that have no connecting edges (they are isolated and routeless)
      if (!adj.containsKey(n.id) || adj[n.id]!.isEmpty) continue;
      
      final d = _haversineDistance(pt.latitude, pt.longitude, n.latitude, n.longitude);
      if (d < bestDist) {
        bestDist = d;
        best = n;
      }
    }
    // Fallback if all nodes are isolated (should be rare)
    return best ?? nodes.first;
  }

  static double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180;
    final lat1Rad = lat1 * math.pi / 180;
    final lat2Rad = lat2 * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2Rad);
    final x = math.cos(lat1Rad) * math.sin(lat2Rad) -
              math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);
    final brng = math.atan2(y, x) * 180 / math.pi;
    return (brng + 360) % 360;
  }

  /// Fetches an external walking route using the OSRM public API (fallback).
  Future<RouteResult> fetchRoute(LatLng from, LatLng to) async {
    // OSRM expects longitude,latitude order
    final coords = '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    final uri = Uri.parse(
      '$_baseUrl/$coords'
      '?steps=true'
      '&geometries=geojson'
      '&overview=full'
      '&annotations=false',
    );

    final response = await http.get(uri).timeout(
      _timeout,
      onTimeout: () => throw Exception('Routing request timed out. Check your internet connection.'),
    );

    if (response.statusCode != 200) {
      throw Exception('Routing API error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final code  = data['code'] as String?;

    if (code != 'Ok') {
      throw Exception('No route found: ${data['message'] ?? code}');
    }

    final routes = data['routes'] as List;
    if (routes.isEmpty) throw Exception('No routes returned.');

    final route = routes[0] as Map<String, dynamic>;

    // ── Polyline from GeoJSON ──────────────────────────────────────────────
    final geometry    = route['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List;
    final polyline = coordinates.map<LatLng>((c) {
      final pair = c as List;
      return LatLng(
        (pair[1] as num).toDouble(),  // lat
        (pair[0] as num).toDouble(),  // lon
      );
    }).toList();

    // ── Distance + Duration ────────────────────────────────────────────────
    final distance = (route['distance'] as num).toDouble();
    final duration = (route['duration'] as num).toDouble();

    // ── Steps ─────────────────────────────────────────────────────────────
    final legs  = route['legs'] as List;
    final steps = <RouteStep>[];
    for (final leg in legs) {
      final legSteps = (leg as Map<String, dynamic>)['steps'] as List? ?? [];
      for (final step in legSteps) {
        steps.add(RouteStep.fromOsrm(step as Map<String, dynamic>));
      }
    }

    return RouteResult(
      polyline:        polyline,
      distanceMetres:  distance,
      durationSeconds: duration,
      steps:           steps,
    );
  }
}
