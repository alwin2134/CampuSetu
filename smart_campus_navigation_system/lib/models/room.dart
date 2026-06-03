import 'package:latlong2/latlong.dart';

class Room {
  final String id;
  final String buildingId;
  final String name;
  final String roomType;
  final int floorLevel;
  final LatLng location;
  final double? altitude;

  Room({
    required this.id,
    required this.buildingId,
    required this.name,
    required this.roomType,
    required this.floorLevel,
    required this.location,
    this.altitude,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'],
      buildingId: json['building_id'],
      name: json['name'],
      roomType: json['room_type'] ?? 'classroom',
      floorLevel: json['floor_level'] ?? 0,
      location: LatLng(json['latitude'], json['longitude']),
      altitude: json['altitude']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'building_id': buildingId,
      'name': name,
      'room_type': roomType,
      'floor_level': floorLevel,
      'latitude': location.latitude,
      'longitude': location.longitude,
      if (altitude != null) 'altitude': altitude,
    };
  }
}
