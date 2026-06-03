class CampusEdge {
  final String id;
  final String sourceNodeId;
  final String targetNodeId;
  final double? distanceMetres;
  final bool isAccessible;
  final DateTime createdAt;

  CampusEdge({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    this.distanceMetres,
    this.isAccessible = true,
    required this.createdAt,
  });

  factory CampusEdge.fromJson(Map<String, dynamic> json) => CampusEdge(
    id:             json['id'] as String,
    sourceNodeId:   json['source_node_id'] as String,
    targetNodeId:   json['target_node_id'] as String,
    distanceMetres: json['distance_metres'] != null
        ? (json['distance_metres'] as num).toDouble()
        : null,
    isAccessible:   (json['is_accessible'] as bool?) ?? true,
    createdAt:      DateTime.parse(json['created_at'] as String),
  );
}
