import 'package:excel_app/home_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证首页视图只负责展示状态并转发用户操作。
void main() {
  testWidgets('renders actions and forwards open-files action', (tester) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HomePageView(
          status: '运行中',
          localIp: '192.168.1.10',
          port: 8080,
          isRunning: true,
          hasFiles: true,
          onStart: () {},
          onStop: () {},
          onOpenFiles: () => opened = true,
        ),
      ),
    );

    expect(find.text('文件接收器'), findsOneWidget);
    expect(find.text('状态: 运行中'), findsOneWidget);
    expect(find.text('打开收到的文件'), findsOneWidget);

    await tester.tap(find.text('打开收到的文件'));
    expect(opened, isTrue);
  });
}
