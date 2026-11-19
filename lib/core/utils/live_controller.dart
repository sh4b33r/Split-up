import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// A controller that listens to live Firestore queries and stops listening
/// when its screen closes.
abstract class LiveController extends GetxController {
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Listens to [stream] until the controller closes. Errors (for example a
  /// permission change after leaving a room) are logged, not thrown.
  StreamSubscription<T> watch<T>(Stream<T> stream, void Function(T value) onData, {void Function(Object)? onError}) {
    final sub = stream.listen(
      onData,
      onError: (Object e) {
        debugPrint('$runtimeType stream error: $e');
        onError?.call(e);
      },
    );
    _subscriptions.add(sub);
    return sub;
  }

  @override
  void onClose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.onClose();
  }
}
