class GraphEdge {
  final String id;
  final String sourceNodeId;
  final String targetNodeId;
  final double distance;
  final bool isAccessible;

  GraphEdge({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    required this.distance,
    required this.isAccessible,
  });

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      id: json['id'],
      sourceNodeId: json['source_node_id'],
      targetNodeId: json['target_node_id'],
      distance: (json['distance'] as num).toDouble(),
      isAccessible: json['is_accessible'] ?? true,
    );
  }
}
