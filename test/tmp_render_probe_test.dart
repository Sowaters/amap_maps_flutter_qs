import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('probe offscreen RepaintBoundary pixels', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => const SizedBox.expand()),
            ],
          ),
        ),
      ),
    );

    final overlay = Overlay.of(
      tester.element(find.byType(Scaffold)),
      rootOverlay: true,
    );
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -20000,
        top: -20000,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: RepaintBoundary(
            key: key,
            child: const DefaultTextStyle(
              style: TextStyle(fontSize: 14, color: Colors.black),
              child: Text('自定义气泡（Widget 快照）666'),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    // ignore: avoid_print
    print(
      'boundary size = ${boundary.size}, needsPaint = ${boundary.debugNeedsPaint}',
    );
    final image = await boundary.toImage(pixelRatio: 3.0);
    // ignore: avoid_print
    print('image = ${image.width}x${image.height}');
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = data!.buffer.asUint8List();
    var nonTransparent = 0;
    for (var i = 3; i < pixels.length; i += 4) {
      if (pixels[i] != 0) nonTransparent++;
    }
    // ignore: avoid_print
    print('nonTransparent pixels = $nonTransparent / ${pixels.length ~/ 4}');
    entry.remove();
  });
}
