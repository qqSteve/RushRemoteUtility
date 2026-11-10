import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/desktop/widgets/rush_dashboard.dart';

void main() {
  testWidgets('access rail keeps rounded rectangle on hover and opens access', (t) async {
    RushAction? selected;
    await t.pumpWidget(MaterialApp(home: RushDashboard(
      hostname: 'Steve', localId: '123', devices: const [], loading: false,
      pending: const {}, onAction: (action) => selected = action,
      onDevice: (_, __) {},
    )));
    final access = find.byTooltip('Подключения и доступ');
    final button = find.descendant(of: access, matching: find.byType(TextButton));
    final shape = t.widget<TextButton>(button).style!.shape!;
    expect(shape.resolve({MaterialState.hovered}), isA<RoundedRectangleBorder>());
    final size = t.getSize(button);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(t.getCenter(button));
    await t.pumpAndSettle();
    expect(t.getSize(button), size);
    await t.tap(button);
    expect(selected, RushAction.legacy);
    await mouse.removePointer();
  });

  testWidgets('responsive grid preserves tile size and peer action targets',
      (t) async {
    final peers =
        List.generate(5, (i) => RushDevice('$i', 'Компьютер $i', '$i', null));
    String? action;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.view.devicePixelRatio = 1;
    for (final layout in [(1280, 3), (1024, 2), (500, 1)]) {
      t.view.physicalSize = Size(layout.$1.toDouble(), 800);
      await t.pumpWidget(MaterialApp(
          home: RushDashboard(
              hostname: 'Работа',
              localId: '',
              devices: peers,
              loading: false,
              pending: {},
              onAction: (_) {},
              onDevice: (peer, a) => action = '${peer.id}/${a.name}')));
      await t.pumpAndSettle();
      final grid = t.widget<GridView>(find.byType(GridView));
      expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          layout.$2);
      final power = t.getSize(find.byTooltip('Разбудить по сети').first);
      expect(power.width, power.height);
      await t.tap(find.text('Подключиться').first);
      expect(action, '0/connect');
      await t.tap(find.byTooltip('Разбудить по сети').first);
      expect(action, '0/wake');
      expect(t.takeException(), isNull);
    }
  });
}
