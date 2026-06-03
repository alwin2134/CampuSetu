import '../models/node.dart';
import '../models/edge.dart';
import 'package:collection/collection.dart';

class PathfindingService {
  /// Finds the shortest path between [startNodeId] and [endNodeId] using Dijkstra's Algorithm.
  /// Returns a list of [GraphNode] representing the path, or an empty list if no path is found.
  static List<GraphNode> findShortestPath({
    required String startNodeId,
    required String endNodeId,
    required List<GraphNode> nodes,
    required List<GraphEdge> edges,
    bool requireAccessible = false,
  }) {
    if (startNodeId == endNodeId) {
      final node = nodes.firstWhereOrNull((n) => n.id == startNodeId);
      return node != null ? [node] : [];
    }

    // Filter edges if accessibility is required
    final availableEdges = requireAccessible
        ? edges.where((e) => e.isAccessible).toList()
        : edges;

    // Create an adjacency list representation of the graph
    // Since edges are usually undirected in a corridor, we add both directions if not explicitly directed.
    // Assuming undirected for campus navigation unless specified otherwise.
    final Map<String, List<MapEntry<String, double>>> adjacencyList = {};
    for (final node in nodes) {
      adjacencyList[node.id] = [];
    }

    for (final edge in availableEdges) {
      if (adjacencyList.containsKey(edge.sourceNodeId) && adjacencyList.containsKey(edge.targetNodeId)) {
        adjacencyList[edge.sourceNodeId]!.add(MapEntry(edge.targetNodeId, edge.distance));
        adjacencyList[edge.targetNodeId]!.add(MapEntry(edge.sourceNodeId, edge.distance)); // Assuming undirected
      }
    }

    // Min-priority queue for Dijkstra
    final PriorityQueue<MapEntry<String, double>> pq = PriorityQueue(
      (a, b) => a.value.compareTo(b.value),
    );

    // Distances map
    final Map<String, double> distances = {};
    for (final node in nodes) {
      distances[node.id] = double.infinity;
    }
    distances[startNodeId] = 0;

    // Previous node map for path reconstruction
    final Map<String, String?> previousNodes = {};

    pq.add(MapEntry(startNodeId, 0.0));

    while (pq.isNotEmpty) {
      final current = pq.removeFirst();
      final currentNodeId = current.key;
      final currentDist = current.value;

      if (currentNodeId == endNodeId) {
        break; // Found the shortest path
      }

      if (currentDist > distances[currentNodeId]!) {
        continue;
      }

      for (final neighbor in adjacencyList[currentNodeId] ?? []) {
        final neighborId = neighbor.key;
        final weight = neighbor.value;
        final newDist = currentDist + weight;

        if (newDist < distances[neighborId]!) {
          distances[neighborId] = newDist;
          previousNodes[neighborId] = currentNodeId;
          pq.add(MapEntry(neighborId, newDist));
        }
      }
    }

    // Reconstruct path
    final List<String> pathIds = [];
    String? currentId = endNodeId;

    if (distances[endNodeId] == double.infinity) {
      return []; // No path found
    }

    while (currentId != null) {
      pathIds.insert(0, currentId);
      currentId = previousNodes[currentId];
    }

    // Map IDs back to Node objects
    final nodeMap = {for (var node in nodes) node.id: node};
    return pathIds.map((id) => nodeMap[id]!).toList();
  }
}
