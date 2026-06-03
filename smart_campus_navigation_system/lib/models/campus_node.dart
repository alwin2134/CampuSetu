class CampusNode {
  final String id;
  final String? campusId;
  final double latitude;
  final double longitude;
  final String nodeType; // 'waypoint' | 'intersection' | 'entrance' | 'landmark'
  final String? name;
  final int floorLevel;
  final double? altitude;
  final DateTime createdAt;

  CampusNode({
    required this.id,
    this.campusId,
    required this.latitude,
    required this.longitude,
    this.nodeType = 'waypoint',
    this.name,
    this.floorLevel = 0,
    this.altitude,
    required this.createdAt,
  });

  factory CampusNode.fromJson(Map<String, dynamic> json) => CampusNode(
    id:        json['id'] as String,
    campusId:  json['campus_id'] as String?,
    latitude:  (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    nodeType:  (json['node_type'] as String?) ?? 'waypoint',
    name:      json['name'] as String?,
    floorLevel: json['floor_level'] ?? 0,
    altitude:  json['altitude'] != null ? (json['altitude'] as num).toDouble() : null,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toInsertJson() => {
    if (campusId != null) 'campus_id': campusId,
    'latitude':  latitude,
    'longitude': longitude,
    'node_type': nodeType,
    if (name != null) 'name': name,
    'floor_level': floorLevel,
    if (altitude != null) 'altitude': altitude,
  };
}
