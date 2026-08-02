import 'package:flutter/foundation.dart';

/// Shared on-screen debug error channel for blank-page diagnosis.
final ValueNotifier<String?> homeDebugError = ValueNotifier<String?>(null);
