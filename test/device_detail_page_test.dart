import 'package:excel_app/device_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows every returned device field without editable controls',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeviceDetailPage(
          data: <String, dynamic>{
            '设备编号': 'P001',
            '设备名称': '设备A',
            '计量日期': '2026-09-01',
          },
        ),
      ),
    );

    expect(find.text('设备详情'), findsOneWidget);
    expect(find.text('设备编号'), findsOneWidget);
    expect(find.text('P001'), findsOneWidget);
    expect(find.text('计量日期'), findsOneWidget);
    expect(find.text('2026-09-01'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('保存'), findsNothing);
  });

  testWidgets('places each detail label and value on one horizontal row',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeviceDetailPage(
          data: <String, dynamic>{'设备编号': 'P001'},
        ),
      ),
    );

    final field = find.byKey(const Key('detail-field-设备编号'));
    expect(field, findsOneWidget);
    final label = find.descendant(of: field, matching: find.text('设备编号'));
    final value = find.descendant(of: field, matching: find.text('P001'));
    expect(label, findsOneWidget);
    expect(value, findsOneWidget);
    expect(
        tester.getTopLeft(value).dx, greaterThan(tester.getTopLeft(label).dx));
    expect(
      (tester.getTopLeft(value).dy - tester.getTopLeft(label).dy).abs(),
      lessThan(20),
    );
  });
}
