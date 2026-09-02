import 'package:carelink/models/person_follower_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PersonFollowerMode Firestore 변환', () {
    test('앱 모드를 대문자 Firestore 값으로 변환한다', () {
      expect(PersonFollowerMode.follow.firestoreValue, 'FOLLOW');
      expect(PersonFollowerMode.stop.firestoreValue, 'STOP');
    });

    test('FOLLOW만 추종으로 읽고 나머지는 안전하게 STOP으로 읽는다', () {
      expect(
        PersonFollowerMode.fromFirestore('FOLLOW'),
        PersonFollowerMode.follow,
      );
      expect(PersonFollowerMode.fromFirestore('STOP'), PersonFollowerMode.stop);
      expect(
        PersonFollowerMode.fromFirestore('follow'),
        PersonFollowerMode.stop,
      );
      expect(
        PersonFollowerMode.fromFirestore('INVALID'),
        PersonFollowerMode.stop,
      );
      expect(PersonFollowerMode.fromFirestore(null), PersonFollowerMode.stop);
    });
  });
}
