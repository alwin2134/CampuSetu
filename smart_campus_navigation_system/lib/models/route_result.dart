import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

// ── Maneuver type → icon ───────────────────────────────────────────────────
IconData maneuverIcon(String type, String modifier) {
  if (type == 'depart') return Icons.navigation_rounded;
  if (type == 'arrive') return Icons.place_rounded;
  if (type == 'roundabout' || type == 'rotary') return Icons.roundabout_right_rounded;
  if (type == 'exit roundabout' || type == 'exit rotary') return Icons.subdirectory_arrow_right_rounded;
  switch (modifier) {
    case 'left':        return Icons.turn_left_rounded;
    case 'right':       return Icons.turn_right_rounded;
    case 'sharp left':  return Icons.turn_sharp_left_rounded;
    case 'sharp right': return Icons.turn_sharp_right_rounded;
    case 'slight left': return Icons.turn_slight_left_rounded;
    case 'slight right':return Icons.turn_slight_right_rounded;
    case 'uturn':       return Icons.u_turn_left_rounded;
    default:            return Icons.straight_rounded;
  }
}

// ── Human-readable instruction ─────────────────────────────────────────────
String buildInstruction(String type, String modifier, String name) {
  final via = name.isNotEmpty ? ' onto $name' : '';
  switch (type) {
    case 'depart':
      return 'Start${via.isNotEmpty ? via : ' heading forward'}';
    case 'arrive':
      return 'Arrive at your destination';
    case 'turn':
      switch (modifier) {
        case 'left':        return 'Turn left$via';
        case 'right':       return 'Turn right$via';
        case 'sharp left':  return 'Turn sharp left$via';
        case 'sharp right': return 'Turn sharp right$via';
        case 'slight left': return 'Bear left$via';
        case 'slight right':return 'Bear right$via';
        case 'uturn':       return 'Make a U-turn$via';
        default:            return 'Continue straight$via';
      }
    case 'continue':
    case 'new name':
      return 'Continue${via.isNotEmpty ? via : ' straight'}';
    case 'merge':           return 'Merge$via';
    case 'roundabout':      return 'Take the roundabout$via';
    case 'exit roundabout': return 'Exit the roundabout$via';
    case 'fork':
      return modifier.contains('left') ? 'Keep left$via' : 'Keep right$via';
    default:
      return 'Continue${via.isNotEmpty ? via : ''}';
  }
}

// ── RouteStep ──────────────────────────────────────────────────────────────
class RouteStep {
  final String instruction;
  final double distanceMetres;
  final String maneuverType;
  final String maneuverModifier;

  RouteStep({
    required this.instruction,
    required this.distanceMetres,
    required this.maneuverType,
    required this.maneuverModifier,
  });

  IconData get icon => maneuverIcon(maneuverType, maneuverModifier);

  String get distanceLabel {
    if (distanceMetres < 10)  return '';
    if (distanceMetres < 1000) return '${distanceMetres.round()} m';
    return '${(distanceMetres / 1000).toStringAsFixed(1)} km';
  }

  factory RouteStep.fromOsrm(Map<String, dynamic> json) {
    final maneuver  = json['maneuver'] as Map<String, dynamic>? ?? {};
    final type      = (maneuver['type']     as String?) ?? 'continue';
    final modifier  = (maneuver['modifier'] as String?) ?? '';
    final name      = (json['name']         as String?) ?? '';
    final distance  = (json['distance']     as num?)?.toDouble() ?? 0;

    return RouteStep(
      instruction:      buildInstruction(type, modifier, name),
      distanceMetres:   distance,
      maneuverType:     type,
      maneuverModifier: modifier,
    );
  }
}

// ── RouteResult ────────────────────────────────────────────────────────────
class RouteResult {
  final List<LatLng> polyline;
  final double distanceMetres;
  final double durationSeconds;
  final List<RouteStep> steps;

  RouteResult({
    required this.polyline,
    required this.distanceMetres,
    required this.durationSeconds,
    required this.steps,
  });

  String get distanceLabel {
    if (distanceMetres < 1000) return '${distanceMetres.round()} m';
    return '${(distanceMetres / 1000).toStringAsFixed(1)} km';
  }

  String get durationLabel {
    final mins = (durationSeconds / 60).round();
    if (mins < 1) return '< 1 min';
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
