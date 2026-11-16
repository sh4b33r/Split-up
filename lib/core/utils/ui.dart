import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/api.dart';

/// Small helpers for feedback and dialogs, so controllers stay short.
class Ui {
  Ui._();

  static void toast(String message, {bool error = false}) {
    final context = Get.context;
    if (context == null) return;
    final scheme = Theme.of(context).colorScheme;
    Get.closeAllSnackbars();
    Get.showSnackbar(GetSnackBar(
      message: message,
      duration: Duration(seconds: error ? 4 : 2),
      margin: const EdgeInsets.all(12),
      borderRadius: 14,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: error ? scheme.error : scheme.inverseSurface,
      messageText: Text(
        message,
        style: TextStyle(color: error ? scheme.onError : scheme.onInverseSurface, fontWeight: FontWeight.w500),
      ),
      icon: Icon(
        error ? Icons.error_outline : Icons.check_circle_outline,
        color: error ? scheme.onError : scheme.onInverseSurface,
      ),
    ));
  }

  static String messageOf(Object e) {
    if (e is ApiException) return e.message;
    return 'Something went wrong. Please try again.';
  }

  /// Runs [action], flips [busy] while it runs, and shows any failure as a
  /// message instead of throwing. Returns null when it failed.
  static Future<T?> attempt<T>(Future<T> Function() action, {RxBool? busy, String? success}) async {
    if (busy?.value == true) return null;
    busy?.value = true;
    try {
      final result = await action();
      if (success != null) toast(success);
      return result;
    } catch (e) {
      toast(messageOf(e), error: true);
      return null;
    } finally {
      busy?.value = false;
    }
  }

  static Future<bool> confirm({
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    bool destructive = false,
  }) async {
    final result = await Get.dialog<bool>(Builder(builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
                : null,
            onPressed: () => Get.back(result: true),
            child: Text(confirmLabel),
          ),
        ],
      );
    }));
    return result == true;
  }

  /// Asks for one line of text. Returns null if cancelled or left empty.
  static Future<String?> prompt({
    required String title,
    String? message,
    String? hint,
    String? initial,
    String confirmLabel = 'Save',
    TextInputType? keyboardType,
    int maxLength = 200,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await Get.dialog<String>(AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(message)),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: maxLength,
            keyboardType: keyboardType,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: hint, counterText: ''),
            onSubmitted: (v) => Get.back(result: v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Get.back(result: controller.text), child: Text(confirmLabel)),
      ],
    ));
    final text = result?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }
}
