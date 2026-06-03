class Facility {
  final String id;
  final String floorId;
  final String? nodeId;
  final String name;
  final String type;

  Facility({
    required this.id,
    required this.floorId,
    this.nodeId,
    required this.name,
    required this.type,
  });

  factory Facility.fromJson(Map<String, dynamic> json) {
    return Facility(
      id: json['id'],
      floorId: json['floor_id'],
      nodeId: json['node_id'],
      name: json['name'],
      type: json['type'],
    );
  }
}
