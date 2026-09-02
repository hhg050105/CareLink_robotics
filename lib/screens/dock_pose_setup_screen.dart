import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/navigation_command.dart';
import '../models/robot_map.dart';

class DockPoseSetupScreen extends StatefulWidget {
  const DockPoseSetupScreen({super.key, this.firestore});

  final FirebaseFirestore? firestore;

  @override
  State<DockPoseSetupScreen> createState() => _DockPoseSetupScreenState();
}

class _DockPoseSetupScreenState extends State<DockPoseSetupScreen> {
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;
  RobotMap? _map;
  ui.Image? _decodedMap;
  Offset? _pixelPose;
  double? _yaw;
  bool _loadingMap = true;
  bool _saving = false;
  String? _error;
  String? _progress;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _commandSubscription;

  @override
  void initState() {
    super.initState();
    _loadMap();
  }

  @override
  void dispose() {
    _commandSubscription?.cancel();
    _decodedMap?.dispose();
    super.dispose();
  }

  Future<void> _loadMap() async {
    try {
      final snapshot = await _db.collection('robot_maps').doc('main').get();
      if (!snapshot.exists) throw StateError('robot_maps/main 지도가 없습니다.');
      final map = RobotMap.fromFirestore(snapshot.data()!);
      if (map.mapVersion.isEmpty)
        throw const FormatException('mapVersion이 없습니다.');
      map.validateCoordinateMetadata();
      if (map.imageMimeType != 'image/png') {
        throw FormatException('지원하지 않는 지도 이미지 형식입니다: ${map.imageMimeType}');
      }
      final bytes = await _loadImageBytes(map);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (frame.image.width != map.width || frame.image.height != map.height) {
        frame.image.dispose();
        throw StateError('지도 이미지 크기와 width/height가 일치하지 않습니다.');
      }
      if (!mounted) return;
      setState(() {
        _map = map;
        _decodedMap = frame.image;
        _loadingMap = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMap = false;
        _error = '지도를 불러오지 못했습니다.\n$error';
      });
    }
  }

  Future<Uint8List> _loadImageBytes(RobotMap map) async {
    if (map.imageBytes != null) return map.imageBytes!;
    final url = map.imageUrl;
    if (url == null || url.isEmpty) {
      throw const FormatException(
        'imageUrl, mapImageUrl, imageBytes 또는 imageBase64가 필요합니다.',
      );
    }
    final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<String?> _selectionProblem(Offset pixel) async {
    final map = _map!;
    if (!MapCoordinateConverter(map).isInside(pixel.dx, pixel.dy))
      return '지도 밖은 선택할 수 없습니다.';
    final column = pixel.dx.floor();
    final imageRow = pixel.dy.floor();
    final occupancy = map.occupancy;
    if (occupancy != null) {
      if (occupancy.length != map.width * map.height)
        return 'occupancy 데이터 크기가 지도와 다릅니다.';
      final rosRow = map.height - 1 - imageRow;
      final value = occupancy[rosRow * map.width + column];
      if (value < 0) return '미확인 셀은 선택할 수 없습니다.';
      if (value >= 50) return '장애물 셀은 선택할 수 없습니다.';
      return null;
    }
    final pixels = await _decodedMap!.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (pixels == null) return '지도 셀을 확인할 수 없습니다.';
    final offset = (imageRow * map.width + column) * 4;
    final r = pixels.getUint8(offset);
    final g = pixels.getUint8(offset + 1);
    final b = pixels.getUint8(offset + 2);
    final brightness = (r + g + b) / 3;
    if (brightness <= 50) return '장애물 셀은 선택할 수 없습니다.';
    if (brightness < 250) return '미확인 셀은 선택할 수 없습니다.';
    return null;
  }

  Future<void> _select(Offset pixel) async {
    if (_saving) return;
    final problem = await _selectionProblem(pixel);
    if (!mounted) return;
    if (problem != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() {
      _pixelPose = pixel;
      _yaw = null;
    });
  }

  Future<void> _handleMapTap(Offset pixel) async {
    final pose = _pixelPose;
    if (pose != null && _yaw == null) {
      final dx = pixel.dx - pose.dx;
      final dy = pixel.dy - pose.dy;
      if (dx == 0 && dy == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로봇이 바라볼 방향을 다른 지점으로 선택하세요.')),
        );
        return;
      }
      setState(() => _yaw = NavigationYaw.fromScreenVector(dx, dy));
      return;
    }
    await _select(pixel);
  }

  Future<void> _confirmAndSave() async {
    final pixel = _pixelPose;
    final yaw = _yaw;
    if (pixel == null || yaw == null || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('도크 위치 저장 확인'),
        content: const Text(
          '로봇이 실제 충전 도크에 결합되어 있습니까? 잘못된 위치를 저장하면 주행 위치가 틀어질 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인 후 저장'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final problem = await _selectionProblem(pixel);
    if (problem != null) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }

    final map = _map!;
    final world = MapCoordinateConverter(
      map,
    ).imagePixelToWorld(pixel.dx, pixel.dy);
    final commandId =
        '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(1 << 32)}';
    final mapRef = _db.collection('robot_maps').doc('main');
    final commandRef = _db.collection('robot_commands').doc('navigation');
    setState(() {
      _saving = true;
      _progress = '명령 전송 중';
    });

    try {
      final latestMap = await mapRef.get(
        const GetOptions(source: Source.server),
      );
      if (!latestMap.exists ||
          latestMap.data()?['mapVersion']?.toString() != map.mapVersion) {
        throw StateError('mapVersion이 변경되었습니다. 지도를 다시 불러오세요.');
      }
      await commandRef.set(
        NavigationCommandPayload.setDockPose(
          commandId: commandId,
          mapVersion: map.mapVersion,
          pose: Nav2Pose(x: world.x, y: world.y, yaw: yaw),
          requestedAt: FieldValue.serverTimestamp(),
        ),
      );
      _watchCommand(commandRef, commandId);
    } catch (error) {
      _finishWithError(error.toString());
    }
  }

  void _watchCommand(
    DocumentReference<Map<String, dynamic>> ref,
    String commandId,
  ) {
    _commandSubscription?.cancel();
    _commandSubscription = ref.snapshots().listen((snapshot) {
      final data = snapshot.data();
      if (data == null || data['commandId'] != commandId) return;
      final status = data['status']?.toString();
      if (status == 'ACCEPTED' && mounted)
        setState(() => _progress = '로봇이 명령을 수신했습니다');
      if (status == 'SAVED') {
        _commandSubscription?.cancel();
        if (!mounted) return;
        setState(() {
          _saving = false;
          _progress = null;
        });
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('저장 완료'),
            content: const Text('AMCL 초기 위치와 영구 도크 좌표가 저장되었습니다.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      } else if (status == 'FAILED') {
        _commandSubscription?.cancel();
        _finishWithError(
          data['error']?.toString() ??
              data['errorMessage']?.toString() ??
              data['message']?.toString() ??
              '로봇이 저장에 실패했습니다.',
        );
      }
    }, onError: (Object error) => _finishWithError(error.toString()));
  }

  void _finishWithError(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _progress = null;
    });
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('도크 위치 저장 실패'),
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
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('도크 위치 설정')),
        body: _loadingMap
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!, textAlign: TextAlign.center))
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final map = _map!;
    final pixel = _pixelPose;
    final world = pixel == null
        ? null
        : MapCoordinateConverter(map).imagePixelToWorld(pixel.dx, pixel.dy);
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
                      key: const Key('dock-pose-map'),
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _handleMapTap(
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
                          painter: _MapPainter(
                            image: _decodedMap!,
                            marker: pixel == null
                                ? null
                                : Offset(
                                    pixel.dx * constraints.maxWidth / map.width,
                                    pixel.dy *
                                        constraints.maxHeight /
                                        map.height,
                                  ),
                            yaw: _yaw,
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
            width: 330,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '도크 설정 모드',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('이 화면에서는 목적지·순찰 명령을 보내지 않습니다.'),
                    const SizedBox(height: 20),
                    Text('mapVersion: ${map.mapVersion}'),
                    Text('frame: ${map.frameId}'),
                    Text('x: ${world?.x.toStringAsFixed(3) ?? '-'} m'),
                    Text('y: ${world?.y.toStringAsFixed(3) ?? '-'} m'),
                    Text(
                      _yaw == null
                          ? 'yaw: 방향을 지도에서 선택하세요'
                          : 'yaw: ${_yaw!.toStringAsFixed(3)} rad (${(_yaw! * 180 / math.pi).toStringAsFixed(1)}°)',
                    ),
                    const SizedBox(height: 16),
                    const Text('로봇 정면 방향 (위치 선택 후 방향 지점을 탭)'),
                    Slider(
                      value: _yaw ?? 0,
                      min: -math.pi,
                      max: math.pi,
                      onChanged: _saving || pixel == null
                          ? null
                          : (value) => setState(
                              () => _yaw = NavigationYaw.normalize(value),
                            ),
                    ),
                    const Spacer(),
                    if (_saving) ...[
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 8),
                      Text(_progress ?? '처리 중', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                    ],
                    FilledButton.icon(
                      onPressed: pixel == null || _yaw == null || _saving
                          ? null
                          : _confirmAndSave,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('도크 위치 저장'),
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
}

class _MapPainter extends CustomPainter {
  const _MapPainter({
    required this.image,
    required this.marker,
    required this.yaw,
  });
  final ui.Image image;
  final Offset? marker;
  final double? yaw;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );
    final point = marker;
    if (point == null) return;
    canvas.save();
    canvas.translate(point.dx, point.dy);
    final paint = Paint()..color = Colors.deepOrange;
    canvas.drawCircle(Offset.zero, 10, Paint()..color = Colors.white);
    canvas.drawCircle(Offset.zero, 7, paint);
    if (yaw != null) {
      canvas.rotate(-yaw!);
      final path = Path()
        ..moveTo(18, 0)
        ..lineTo(6, -6)
        ..lineTo(6, 6)
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.marker != marker ||
      oldDelegate.yaw != yaw;
}
