import 'package:flutter/foundation.dart';

/// Additional lifecycle pause only. The original port still owns authorization.
abstract interface class PersonalProfileReadAdmission {
  VoidCallback registerReadAdmission(bool Function() admitsRead);
  void resumeAdmittedReads();
}
