import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:splitup/core/widgets/motion.dart';

void main() {
  testWidgets('confetti appears over the app and removes itself', (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: Text('page'))));
    final before = find.byType(CustomPaint).evaluate().length;
    Confetti.burst(Get.context!);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CustomPaint).evaluate().length, greaterThan(before), reason: 'confetti layer inserted');
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(CustomPaint).evaluate().length, before, reason: 'confetti layer removed');
  });
}
