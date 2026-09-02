import 'package:cloud_firestore/cloud_firestore.dart';

class FallEvent {
  const FallEvent({
    required this.id,
    required this.detectedAt,
    required this.confidence,
    required this.dropPixels,
    required this.cameraId,
    required this.acknowledged,
    required this.snapshotPath,
  });

  final String id;
  final DateTime? detectedAt;
  final double? confidence;
  final double? dropPixels;
  final String cameraId;
  final bool acknowledged;
  final String? snapshotPath;

  factory FallEvent.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data()!;
    return FallEvent(
      id: document.id,
      detectedAt: (data['detectedAt'] as Timestamp?)?.toDate(),
      confidence: (data['confidence'] as num?)?.toDouble(),
      dropPixels: (data['dropPixels'] as num?)?.toDouble(),
      cameraId: data['cameraId']?.toString() ?? '알 수 없음',
      acknowledged: data['acknowledged'] == true,
      snapshotPath: data['snapshotPath']?.toString(),
    );
  }
}

class FallEventRepository {
  FallEventRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('fall_events');

  Stream<List<FallEvent>> watchRecent() => _events
      .orderBy('detectedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(FallEvent.fromDocument).toList());

  Future<FallEvent?> getById(String eventId) async {
    final document = await _events.doc(eventId).get();
    return document.exists ? FallEvent.fromDocument(document) : null;
  }

  Future<void> acknowledge(String eventId) =>
      _events.doc(eventId).update({'acknowledged': true});
}
