import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/navigation_command.dart';
import '../models/robot_map.dart';
import '../styles/app_colors.dart';

class PatrolMapPreviewScreen extends StatefulWidget {
  const PatrolMapPreviewScreen({super.key});
  @override
  State<PatrolMapPreviewScreen> createState() => _PatrolMapPreviewScreenState();
}

class _Point {
  const _Point(this.pixel, [this.yaw]);
  final Offset pixel;
  final double? yaw;
  _Point withPixel(Offset value) => _Point(value, yaw);
  _Point withYaw(double value) => _Point(pixel, NavigationYaw.normalize(value));
}

class _PatrolMapPreviewScreenState extends State<PatrolMapPreviewScreen> {
  final _db = FirebaseFirestore.instance;
  final List<_Point> _points = [];
  RobotMap? _map;
  ui.Image? _image;
  int? _editing;
  bool _loading = true;
  bool _running = false;
  String? _error;
  String? _status;
  String? _patrolId;
  int? _currentPoint;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _watch;

  @override
  void initState() {
    super.initState();
    _loadMap();
  }

  @override
  void dispose() {
    _watch?.cancel();
    _image?.dispose();
    super.dispose();
  }

  Future<Uint8List> _imageBytes(RobotMap map) async {
    if (map.imageBytes != null) return map.imageBytes!;
    final url = map.imageUrl;
    if (url == null || url.isEmpty)
      throw const FormatException('imageBase64 지도 이미지가 없습니다.');
    final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> _loadMap() async {
    try {
      final snapshot = await _db.collection('robot_maps').doc('main').get();
      if (!snapshot.exists) throw StateError('robot_maps/main 지도가 없습니다.');
      final map = RobotMap.fromFirestore(snapshot.data()!);
      map.validateCoordinateMetadata();
      final codec = await ui.instantiateImageCodec(await _imageBytes(map));
      final frame = await codec.getNextFrame();
      if (frame.image.width != map.width || frame.image.height != map.height) {
        frame.image.dispose();
        throw StateError('지도 이미지 크기와 width/height가 일치하지 않습니다.');
      }
      if (!mounted) return;
      setState(() {
        _map = map;
        _image = frame.image;
        _loading = false;
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = '$error';
        });
    }
  }

  Future<String?> _invalidCell(Offset pixel) async {
    final map = _map!;
    if (!MapCoordinateConverter(map).isInside(pixel.dx, pixel.dy))
      return '지도 밖은 선택할 수 없습니다.';
    final x = pixel.dx.floor();
    final imageY = pixel.dy.floor();
    if (map.occupancy != null) {
      if (map.occupancy!.length != map.width * map.height)
        return 'occupancy 데이터 크기가 잘못되었습니다.';
      final value = map.occupancy![(map.height - 1 - imageY) * map.width + x];
      if (value < 0) return '미확인 셀은 선택할 수 없습니다.';
      if (value >= 50) return '장애물 셀은 선택할 수 없습니다.';
      return null;
    }
    final data = await _image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return '지도 셀을 확인할 수 없습니다.';
    final offset = (imageY * map.width + x) * 4;
    final brightness =
        (data.getUint8(offset) +
            data.getUint8(offset + 1) +
            data.getUint8(offset + 2)) /
        3;
    if (brightness <= 50) return '장애물 셀은 선택할 수 없습니다.';
    if (brightness < 250) return '미확인 셀은 선택할 수 없습니다.';
    return null;
  }

  Future<void> _select(Offset pixel) async {
    if (_running) return;
    final problem = await _invalidCell(pixel);
    if (!mounted) return;
    if (problem != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() {
      if (_editing != null) {
        _points[_editing!] = _points[_editing!].withPixel(pixel);
      } else if (_points.length < 3) {
        _points.add(_Point(pixel));
      }
      if (_points.length == 3) {
        for (var index = 0; index < _points.length; index++) {
          final current = _points[index];
          final next = _points[(index + 1) % _points.length];
          final dx = next.pixel.dx - current.pixel.dx;
          final dy = next.pixel.dy - current.pixel.dy;
          if (dx != 0 || dy != 0) {
            _points[index] = current.withYaw(
              NavigationYaw.fromScreenVector(dx, dy),
            );
          }
        }
      }
    });
  }

  int? get _yawIndex =>
      _editing ?? (_points.isEmpty ? null : _points.length - 1);

  Future<void> _start() async {
    if (_points.length != 3 ||
        _points.any((point) => point.yaw == null) ||
        _running) {
      return;
    }
    final map = _map!;
    final mapRef = _db.collection('robot_maps').doc('main');
    final commandRef = _db.collection('robot_commands').doc('navigation');
    final id =
        'patrol-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}';
    setState(() {
      _running = true;
      _status = 'REQUESTED';
      _patrolId = id;
      _currentPoint = null;
    });
    try {
      final latest = await mapRef.get(const GetOptions(source: Source.server));
      final version = latest.data()?['mapVersion']?.toString();
      if (!latest.exists || version != map.mapVersion)
        throw StateError('mapVersion이 변경되었습니다. 화면을 다시 열어주세요.');
      final converter = MapCoordinateConverter(map);
      await commandRef.set(
        NavigationCommandPayload.patrol(
          commandId: id,
          mapVersion: version!,
          points: _points
              .map((point) {
                final world = converter.imagePixelToWorld(
                  point.pixel.dx,
                  point.pixel.dy,
                );
                return Nav2Pose(x: world.x, y: world.y, yaw: point.yaw!);
              })
              .toList(growable: false),
          requestedAt: FieldValue.serverTimestamp(),
        ),
      );
      _listen(commandRef, id);
    } catch (error) {
      _fail('$error');
    }
  }

  void _listen(DocumentReference<Map<String, dynamic>> ref, String id) {
    _watch?.cancel();
    _watch = ref.snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (!mounted || data == null || data['commandId'] != id) return;
      final status = data['status']?.toString();
      if (status == 'ACCEPTED' || status == 'MOVING') {
        setState(() {
          _status = status;
          _currentPoint = (data['currentPoint'] as num?)?.toInt();
        });
      } else if (status == 'ARRIVED') {
        _watch?.cancel();
        setState(() {
          _running = false;
          _status = 'ARRIVED';
          _currentPoint = 3;
        });
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('순찰 완료'),
            content: const Text('3개 지점 순찰을 완료했습니다.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      } else if (status == 'FAILED') {
        _watch?.cancel();
        _fail(
          data['error']?.toString() ??
              data['errorMessage']?.toString() ??
              data['message']?.toString() ??
              '순찰에 실패했습니다.',
        );
      }
    }, onError: (Object error) => _fail('$error'));
  }

  Future<void> _cancel() async {
    final target = _patrolId;
    if (!_running || target == null) return;
    final id =
        'cancel-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}';
    try {
      await _db.collection('robot_commands').doc('navigation').set({
        'command': 'CANCEL',
        'commandId': id,
        'targetCommandId': target,
        'status': 'REQUESTED',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      await _watch?.cancel();
      if (mounted)
        setState(() {
          _running = false;
          _status = '취소 요청됨';
        });
    } catch (error) {
      _fail('$error');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _running = false;
      _status = 'FAILED';
    });
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('순찰 실패'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_running,
    child: Scaffold(
      appBar: AppBar(title: const Text('3지점 순찰 설정')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                '지도를 불러오지 못했습니다.\n$_error',
                textAlign: TextAlign.center,
              ),
            )
          : _content(),
    ),
  );

  Widget _content() {
    final map = _map!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: map.width / map.height,
                child: LayoutBuilder(
                  builder: (context, constraints) => InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 8,
                    child: GestureDetector(
                      key: const Key('patrol-map'),
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _select(
                        Offset(
                          details.localPosition.dx *
                              map.width /
                              constraints.maxWidth,
                          details.localPosition.dy *
                              map.height /
                              constraints.maxHeight,
                        ),
                      ),
                      child: SizedBox.expand(
                        child: CustomPaint(
                          painter: _Painter(
                            image: _image!,
                            points: _points
                                .map(
                                  (point) => _Point(
                                    Offset(
                                      point.pixel.dx *
                                          constraints.maxWidth /
                                          map.width,
                                      point.pixel.dy *
                                          constraints.maxHeight /
                                          map.height,
                                    ),
                                    point.yaw,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 370,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '순찰 지점',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('지도에서 순서대로 3개 지점을 선택하세요.'),
                    const SizedBox(height: 8),
                    for (var index = 0; index < 3; index++)
                      _pointRow(index, map),
                    Text(
                      _yawIndex == null
                          ? '지점을 먼저 선택하세요.'
                          : '${_yawIndex! + 1}번 지점 방향',
                    ),
                    Slider(
                      value: _yawIndex == null
                          ? 0
                          : (_points[_yawIndex!].yaw ?? 0),
                      min: -math.pi,
                      max: math.pi,
                      onChanged: _running || _yawIndex == null
                          ? null
                          : (value) => setState(() {
                              final index = _yawIndex!;
                              _points[index] = _points[index].withYaw(value);
                            }),
                    ),
                    if (_status != null)
                      Text(
                        _status == 'MOVING'
                            ? '이동 중: ${_currentPoint ?? '-'} / 3'
                            : '상태: $_status',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    if (_running) const LinearProgressIndicator(),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _running
                          ? _cancel
                          : _points.isEmpty
                          ? null
                          : () => setState(() {
                              _points.clear();
                              _editing = null;
                              _status = null;
                            }),
                      icon: Icon(
                        _running ? Icons.stop_rounded : Icons.refresh_rounded,
                      ),
                      label: Text(_running ? '순찰 취소' : '다시 선택'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed:
                          _points.length == 3 &&
                              _points.every((point) => point.yaw != null) &&
                              !_running
                          ? _start
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                      ),
                      icon: const Icon(Icons.route_rounded),
                      label: const Text('3지점 순찰 시작'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pointRow(int index, RobotMap map) {
    if (index >= _points.length)
      return ListTile(
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: const Text('지도에서 선택'),
      );
    final point = _points[index];
    final world = MapCoordinateConverter(
      map,
    ).imagePixelToWorld(point.pixel.dx, point.pixel.dy);
    return ListTile(
      selected: _editing == index,
      onTap: _running ? null : () => setState(() => _editing = index),
      leading: CircleAvatar(child: Text('${index + 1}')),
      title: Text(
        'x ${world.x.toStringAsFixed(2)}, y ${world.y.toStringAsFixed(2)}',
      ),
      subtitle: Text(
        point.yaw == null
            ? 'yaw 방향 미지정'
            : 'yaw ${point.yaw!.toStringAsFixed(2)} rad',
      ),
    );
  }
}

class _Painter extends CustomPainter {
  const _Painter({required this.image, required this.points});
  final ui.Image image;
  final List<_Point> points;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      canvas.save();
      canvas.translate(point.pixel.dx, point.pixel.dy);
      final paint = Paint()..color = AppColors.purple;
      canvas.drawCircle(Offset.zero, 13, Paint()..color = Colors.white);
      canvas.drawCircle(Offset.zero, 10, paint);
      if (point.yaw != null) {
        canvas.rotate(-point.yaw!);
        canvas.drawPath(
          Path()
            ..moveTo(18, 0)
            ..lineTo(6, -6)
            ..lineTo(6, 6)
            ..close(),
          paint,
        );
      }
      canvas.restore();
      final label = TextPainter(
        text: TextSpan(
          text: '${index + 1}',
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        point.pixel - Offset(label.width / 2, label.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Painter oldDelegate) => true;
}
