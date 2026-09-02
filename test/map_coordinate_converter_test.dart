import 'package:carelink/models/robot_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const map = RobotMap(
    mapVersion: 'v1',
    resolution: 0.05,
    width: 200,
    height: 100,
    originX: -5,
    originY: -2,
    pixelOrigin: 'top-left',
    pixelXDirection: 'right',
    pixelYDirection: 'down',
  );
  const converter = MapCoordinateConverter(map);

  test('top-left image coordinate converts to ROS top-left world coordinate', () {
    final world = converter.imagePixelToWorld(0, 0);
    expect(world.x, -5);
    expect(world.y, 3);
  });

  test('bottom-left image coordinate converts using inverted y axis', () {
    final world = converter.imagePixelToWorld(0, 100);
    expect(world.x, -5);
    expect(world.y, -2);
  });

  test('conversion is based on map pixels, independent of display scale', () {
    final world = converter.imagePixelToWorld(100, 50);
    expect(world.x, 0);
    expect(world.y, 0.5);
  });
}
