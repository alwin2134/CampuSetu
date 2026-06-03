class GraphNode {
  final String id;
  final String floorId;
  final double latitude;
  final double longitude;
  final String nodeType;

  GraphNode({
    required this.id,
    required this.floorId,
    required this.latitude,
    required this.longitude,
    required this.nodeType,
  });

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'],
      floorId: json['floor_id'],
      latitude: (json['y_coordinate'] as num).toDouble(), // Map y to lat
      longitude: (json['x_coordinate'] as num).toDouble(), // Map x to lng
      nodeType: json['node_type'],
    );
  }
}
