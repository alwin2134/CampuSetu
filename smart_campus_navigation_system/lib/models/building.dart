class Building {
  final String id;
  final String campusId;
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final DateTime createdAt;

  Building({
    required this.id,
    required this.campusId,
    required this.name,
    this.description,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(
      id: json['id'],
      campusId: json['campus_id'],
      name: json['name'],
      description: json['description'],
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : 0.0,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : 0.0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'campus_id': campusId,
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
