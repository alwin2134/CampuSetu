class Event {
  final String id;
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final DateTime? eventTime;
  final DateTime createdAt;

  Event({
    required this.id,
    required this.name,
    this.description,
    required this.latitude,
    required this.longitude,
    this.eventTime,
    required this.createdAt,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      eventTime: json['event_time'] != null ? DateTime.parse(json['event_time']) : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      if (eventTime != null) 'event_time': eventTime!.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
