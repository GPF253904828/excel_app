import 'package:excel_app/export_page.dart';
import 'package:excel_app/home_page_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证导出页复用统一文件服务的状态和控制入口。
void main() {
  testWidgets('renders export service controls', (tester) async {
    final controller = HomePageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ExportPage(controller: controller)),
    );

    expect(find.text('导出'), findsOneWidget);
    expect(find.text('状态: 未启动'), findsOneWidget);
    expect(find.text('启动服务'), findsOneWidget);
  });
}
