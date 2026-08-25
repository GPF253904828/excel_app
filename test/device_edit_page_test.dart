import 'package:excel_app/device_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saves a complete new row and returns it', (tester) async {
    List<String>? savedRow;
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEditPage(
          headers: const ['设备编号', '设备名称', '备注'],
          initialRow: const ['', '设备A'],
          isNew: true,
          onSave: (row) async => savedRow = row,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('field-设备编号')), 'P002');
    await tester.enterText(find.byKey(const Key('field-设备名称')), '设备B');
    await tester.enterText(find.byKey(const Key('field-备注')), '首行');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(savedRow, const ['P002', '设备B', '首行']);
    expect(find.byType(DeviceEditPage), findsNothing);
  });

  testWidgets('keeps the existing device code read-only by default',
      (tester) async {
    await tester.pumpWidget(_buildPage(isNew: false));

    expect(
      tester.widget<TextField>(find.byKey(const Key('field-设备编号'))).enabled,
      isFalse,
    );
    expect(find.byTooltip('修改设备编码'), findsOneWidget);
  });

  testWidgets('enables the existing device code after confirmation',
      (tester) async {
    await tester.pumpWidget(_buildPage(isNew: false));

    await tester.tap(find.byTooltip('修改设备编码'));
    await tester.pump();
    expect(find.text('确认修改设备编码'), findsOneWidget);
    expect(find.text('改编码可能影响行匹配'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确认修改'), findsOneWidget);

    await tester.tap(find.text('确认修改'));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byKey(const Key('field-设备编号'))).enabled,
      isTrue,
    );
  });

  testWidgets('keeps the existing device code read-only after cancellation',
      (tester) async {
    await tester.pumpWidget(_buildPage(isNew: false));

    await tester.tap(find.byTooltip('修改设备编码'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byKey(const Key('field-设备编号'))).enabled,
      isFalse,
    );
  });

  testWidgets('keeps the page and entered values when saving fails',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceEditPage(
          headers: const ['设备编号', '设备名称'],
          initialRow: const ['P001', '设备A'],
          isNew: true,
          onSave: (_) async => throw '网络错误',
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('field-设备名称')), '设备B');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.byType(DeviceEditPage), findsOneWidget);
    expect(find.text('保存失败: 网络错误'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('field-设备名称')))
          .controller!
          .text,
      '设备B',
    );
  });
}

/// Builds a test page with a stable existing or new row configuration.
Widget _buildPage({required bool isNew}) {
  return MaterialApp(
    home: DeviceEditPage(
      headers: const ['设备编号', '设备名称'],
      initialRow: const ['P001', '设备A'],
      isNew: isNew,
      onSave: (_) async {},
    ),
  );
}
