import 'package:excel_app/home_page.dart';
import 'package:excel_app/home_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证首页大厅只展示在线和本地两个入口并转发导航操作。
void main() {
  testWidgets('renders online and local actions', (tester) async {
    var openedOnline = false;
    var openedLocal = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HomePageView(
          onOnlinePage: () => openedOnline = true,
          onLocalPage: () => openedLocal = true,
        ),
      ),
    );

    expect(find.text('大厅'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('本地'), findsOneWidget);
    expect(find.text('打开收到的文件'), findsNothing);

    await tester.tap(find.text('在线'));
    await tester.tap(find.text('本地'));

    expect(openedOnline, isTrue);
    expect(openedLocal, isTrue);
  });

  testWidgets('opens the local configuration page', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    await tester.tap(find.text('本地'));
    await tester.pumpAndSettle();

    expect(find.text('本地配置'), findsOneWidget);
  });
}
