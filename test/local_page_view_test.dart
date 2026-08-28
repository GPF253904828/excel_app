import 'package:excel_app/local_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证本地配置页保留文件传输和已接收文件管理入口。
void main() {
  testWidgets('renders local transfer controls', (tester) async {
    var stopped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: LocalPageView(
          status: '运行中',
          localIp: '192.168.1.10',
          port: 8080,
          isRunning: true,
          hasFiles: true,
          onStart: () {},
          onStop: () => stopped = true,
          onOpenFiles: () {},
          onDeleteFiles: () {},
        ),
      ),
    );

    expect(find.text('本地配置'), findsOneWidget);
    expect(find.text('状态: 运行中'), findsOneWidget);
    expect(find.text('http://192.168.1.10:8080'), findsOneWidget);
    expect(find.text('启动服务'), findsOneWidget);
    expect(find.text('停止服务'), findsOneWidget);
    expect(find.text('打开收到的文件'), findsOneWidget);
    expect(find.text('删除本地文件'), findsOneWidget);

    await tester.tap(find.text('停止服务'));
    expect(stopped, isTrue);
  });
}
