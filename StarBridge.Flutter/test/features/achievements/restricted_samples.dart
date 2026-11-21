import 'dart:io';

import '../../_support/restricted_files.dart';

File restrictedAchievementSample(String name) =>
    File('../contracts/achievements/$name');

String? restrictedSampleSkipReason(String testName, File sample) =>
    restrictedFileSkip(testName, 'sample', sample.path);
