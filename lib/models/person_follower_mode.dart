enum PersonFollowerMode {
  follow,
  stop;

  String get firestoreValue => switch (this) {
    PersonFollowerMode.follow => 'FOLLOW',
    PersonFollowerMode.stop => 'STOP',
  };

  static PersonFollowerMode fromFirestore(Object? value) {
    return value == 'FOLLOW'
        ? PersonFollowerMode.follow
        : PersonFollowerMode.stop;
  }
}
