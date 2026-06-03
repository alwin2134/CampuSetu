class Floor {
  final String id;
  final String buildingId;
  final int floorNumber;
  final String? mapImageUrl;
  final double scaleFactor;
  final DateTime createdAt;

  Floor({
    required this.id,
    required this.buildingId,
    required this.floorNumber,
    this.mapImageUrl,
    required this.scaleFactor,
    required this.createdAt,
  });

  factory Floor.fromJson(Map<String, dynamic> json) {
    return Floor(
      id: json['id'],
      buildingId: json['building_id'],
      floorNumber: json['floor_number'],
      mapImageUrl: json['map_image_url'],
      scaleFactor: (json['scale_factor'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'building_id': buildingId,
      'floor_number': floorNumber,
      'map_image_url': mapImageUrl,
      'scale_factor': scaleFactor,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
