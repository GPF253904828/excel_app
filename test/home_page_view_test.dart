import 'package:excel_app/home_page.dart';
import 'package:excel_app/home_page_view.dart';
import 'package:excel_app/device_detail_page.dart';
import 'package:excel_app/device_edit_page.dart';
import 'package:excel_app/online/online_config_store.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 验证首页大厅只展示在线和本地入口并转发导航操作。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('renders online scan, list, and local actions without export',
      (tester) async {
    var openedOnlineScan = false;
    var openedOnlineList = false;
    var openedLocal = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HomePageView(
          onOnlineScan: () => openedOnlineScan = true,
          onOnlineList: () => openedOnlineList = true,
          onLocalPage: () => openedLocal = true,
        ),
      ),
    );

    expect(find.text('大厅'), findsOneWidget);
    expect(find.text('在线扫码'), findsOneWidget);
    expect(find.text('在线查看全部'), findsOneWidget);
    expect(find.text('本地'), findsOneWidget);
    expect(find.text('导出'), findsNothing);
    expect(find.text('打开收到的文件'), findsNothing);

    await tester.tap(find.text('在线扫码'));
    await tester.tap(find.text('在线查看全部'));
    await tester.tap(find.text('本地'));

    expect(openedOnlineScan, isTrue);
    expect(openedOnlineList, isTrue);
    expect(openedLocal, isTrue);
  });

  testWidgets('opens the local configuration page', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    await tester.tap(find.text('本地'));
    await tester.pumpAndSettle();

    expect(find.text('本地配置'), findsOneWidget);
  });

  testWidgets('online scan queries the latest device before showing details',
      (tester) async {
    _mockScannerChannel();
    final requestedNumbers = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          onQuery: (deviceNo, config) async {
            requestedNumbers.add(deviceNo);
            return DeviceResult.fromJson(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                '设备编号': deviceNo,
                '计量日期': '2026-09-01',
              },
            });
          },
        ),
      ),
    );

    await tester.tap(find.text('在线扫码'));
    await tester.pumpAndSettle();
    tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect(
          BarcodeCapture(barcodes: [const Barcode(rawValue: 'P001')]),
        );
    await tester.pumpAndSettle();

    expect(requestedNumbers, ['P001']);
    expect(find.byType(DeviceDetailPage), findsOneWidget);
    expect(find.text('2026-09-01'), findsOneWidget);
    expect(find.byType(DeviceEditPage), findsNothing);
  });

  testWidgets('failed online scan does not open a device detail page',
      (tester) async {
    _mockScannerChannel();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          onQuery: (deviceNo, config) async => DeviceResult.fromJson(
            <String, dynamic>{
              'success': false,
              'message': '未找到设备',
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('在线扫码'));
    await tester.pumpAndSettle();
    tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect(
          BarcodeCapture(barcodes: [const Barcode(rawValue: 'P001')]),
        );
    await tester.pumpAndSettle();

    expect(find.byType(DeviceDetailPage), findsNothing);
  });

  testWidgets('shows a loading message while online scan is querying',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePageView(
          isOnlineLoading: true,
          onOnlineScan: () {},
          onOnlineList: () {},
          onLocalPage: () {},
        ),
      ),
    );

    expect(find.text('正在获取数据...'), findsOneWidget);
  });

  testWidgets('passes the selected config store to the full online list',
      (tester) async {
    final store = _TrackingOnlineConfigStore();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          configStore: store,
          onList: ({required start, required limit}) async =>
              DeviceListResult.fromJson(<String, dynamic>{
            'success': true,
            'total': 0,
            'start': start,
            'limit': limit,
            'hasMore': false,
            'rows': <Map<String, dynamic>>[],
          }),
        ),
      ),
    );

    await tester.tap(find.text('在线查看全部'));
    await tester.pump();

    expect(store.loadCount, greaterThan(0));
  });
}

/// 记录在线列表初始化时是否使用了首页传入的配置存储。
class _TrackingOnlineConfigStore extends OnlineConfigStore {
  int loadCount = 0;

  @override
  Future<OnlineApiConfig?> load() async {
    loadCount++;
    return OnlineApiConfig.builtIn;
  }
}

/// 为扫码路由提供拒绝权限的最小 platform channel 响应。
void _mockScannerChannel() {
  const methodChannel = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );
  TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
      .setMockMethodCallHandler(methodChannel, (call) async {
    if (call.method == 'state') return 0;
    if (call.method == 'request') return false;
    return true;
  });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });
}
