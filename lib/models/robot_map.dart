import 'dart:convert';
import 'dart:typed_data';

class RobotMap {
  const RobotMap({
    required this.mapVersion,
    required this.resolution,
    required this.width,
    required this.height,
    required this.originX,
    required this.originY,
    this.imageUrl,
    this.imageBytes,
    this.occupancy,
    this.imageMimeType = 'image/png',
    this.frameId = 'map',
    this.pixelOrigin = 'top-left',
    this.pixelXDirection = 'right',
    this.pixelYDirection = 'down',
  });

  factory RobotMap.fromFirestore(Map<String, dynamic> data) {
    final origin = data['origin'];
    final originX = origin is List && origin.isNotEmpty
        ? _number(origin[0], 'origin[0]')
        : _number((origin as Map?)?['x'], 'origin.x');
    final originY = origin is List && origin.length > 1
        ? _number(origin[1], 'origin[1]')
        : _number((origin as Map?)?['y'], 'origin.y');
    final encoded = data['imageBase64'];
    final rawBytes = data['imageBytes'];

    return RobotMap(
      mapVersion: data['mapVersion']?.toString() ?? '',
      resolution: _number(data['resolution'], 'resolution'),
      width: _integer(data['width'], 'width'),
      height: _integer(data['height'], 'height'),
      originX: originX,
      originY: originY,
      imageUrl: (data['imageUrl'] ?? data['mapImageUrl'] ?? data['url'])?.toString(),
      imageBytes: rawBytes is Uint8List
          ? rawBytes
          : rawBytes is List
              ? Uint8List.fromList(rawBytes.cast<int>())
              : encoded is String
                  ? base64Decode(encoded.contains(',') ? encoded.split(',').last : encoded)
                  : null,
      occupancy: data['occupancy'] is List
          ? (data['occupancy'] as List).map((value) => (value as num).toInt()).toList(growable: false)
          : null,
      imageMimeType: data['imageMimeType']?.toString() ?? 'image/png',
      frameId: data['frameId']?.toString() ?? 'map',
      pixelOrigin: data['pixelOrigin']?.toString() ?? 'top-left',
      pixelXDirection: data['pixelXDirection']?.toString() ?? 'right',
      pixelYDirection: data['pixelYDirection']?.toString() ?? 'down',
    );
  }

  final String mapVersion;
  final double resolution;
  final int width;
  final int height;
  final double originX;
  final double originY;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final List<int>? occupancy;
  final String imageMimeType;
  final String frameId;
  final String pixelOrigin;
  final String pixelXDirection;
  final String pixelYDirection;

  void validateCoordinateMetadata() {
    if (frameId != 'map') {
      throw FormatException('지원하지 않는 frameId입니다: $frameId');
    }
    final normalizedOrigin = _normalize(pixelOrigin);
    if (normalizedOrigin != 'topleft' ||
        _normalize(pixelXDirection) != 'right' ||
        _normalize(pixelYDirection) != 'down') {
      throw FormatException(
        '현재 지도 좌표계는 top-left/right/down이어야 합니다. '
        '수신값: $pixelOrigin/$pixelXDirection/$pixelYDirection',
      );
    }
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[_\s-]'), '');

  static double _number(Object? value, String field) {
    if (value is num) return value.toDouble();
    throw FormatException('robot_maps/main의 $field 값이 올바르지 않습니다.');
  }

  static int _integer(Object? value, String field) {
    if (value is num && value.toInt() > 0) return value.toInt();
    throw FormatException('robot_maps/main의 $field 값이 올바르지 않습니다.');
  }
}

class MapCoordinateConverter {
  const MapCoordinateConverter(this.map);

  final RobotMap map;

  ({double x, double y}) imagePixelToWorld(double pixelX, double pixelY) {
    map.validateCoordinateMetadata();
    return (
      x: map.originX + pixelX * map.resolution,
      y: map.originY + (map.height - pixelY) * map.resolution,
    );
  }

  bool isInside(double pixelX, double pixelY) =>
      pixelX >= 0 && pixelX < map.width && pixelY >= 0 && pixelY < map.height;
}
