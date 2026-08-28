import 'package:excel_app/online/online_page.dart';
import 'package:excel_app/device_edit_page.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证在线设备页面的固定字段展示入口已经存在。
void main() {
  testWidgets('查询成功后按固定 15 列展示整行数据', (tester) async {
    await _pumpWidget(
      tester,
      _app(
        onQuery: (_) async => _result(
          type: 'query',
          deviceNo: 'P001',
          data: _deviceData(deviceNo: 'P001'),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('online-device-no')), ' P001 ');
    await tester.tap(find.byKey(const Key('online-query')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('online-column-归属部门')), findsOneWidget);
    expect(find.byKey(const Key('online-column-计量有效期至')), findsOneWidget);
    expect(find.byKey(const Key('online-value-设备编号')), findsOneWidget);
    expect(find.text('设备名称-P001'), findsOneWidget);
    expect(find.text('查询成功'), findsOneWidget);
  });

  testWidgets('查询失败显示接口消息', (tester) async {
    await _pumpWidget(
      tester,
      _app(
        onQuery: (_) async => _result(
          type: 'query',
          success: false,
          message: '未找到设备编号: P999',
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('online-device-no')), 'P999');
    await tester.tap(find.byKey(const Key('online-query')));
    await tester.pumpAndSettle();

    expect(find.text('未找到设备编号: P999'), findsOneWidget);
  });

  testWidgets('修改编辑后的整行并用原设备编号调用接口', (tester) async {
    String? modifiedNo;
    Map<String, dynamic>? modifiedData;
    await _pumpWidget(
      tester,
      _app(
        onQuery: (_) async => _result(
          type: 'query',
          deviceNo: 'P001',
          data: _deviceData(deviceNo: 'P001'),
        ),
        onModify: (no, data) async {
          modifiedNo = no;
          modifiedData = data;
          return _result(
            type: 'modify',
            deviceNo: no,
            data: {...data, '设备名称': '修改后设备'},
          );
        },
      ),
    );

    await _queryDevice(tester, 'P001');
    await tester.ensureVisible(find.byKey(const Key('online-edit')));
    await tester.tap(find.byKey(const Key('online-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-设备名称')), '修改后设备');
    await _saveEditor(tester);

    expect(find.byType(DeviceEditPage), findsNothing);
    expect(modifiedNo, 'P001');
    expect(modifiedData?['设备名称'], '修改后设备');
    expect(find.text('修改后设备'), findsOneWidget);
    expect(find.text('修改成功'), findsOneWidget);
  });

  testWidgets('新增整行并展示接口返回的新设备', (tester) async {
    Map<String, dynamic>? addedData;
    await _pumpWidget(
      tester,
      _app(
        onAdd: (data) async {
          addedData = data;
          return _result(
            type: 'add',
            deviceNo: 'P002',
            data: {...data, '设备编号': 'P002', '设备名称': '新增设备'},
          );
        },
      ),
    );

    await tester.tap(find.byKey(const Key('online-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-设备编号')), 'P002');
    await tester.enterText(find.byKey(const Key('field-设备名称')), '新增设备');
    await _saveEditor(tester);

    expect(find.byType(DeviceEditPage), findsNothing);
    expect(addedData?['设备编号'], 'P002');
    expect(find.byKey(const Key('online-value-设备编号')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('online-value-设备名称')),
        matching: find.text('新增设备'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('online-device-no')))
          .controller!
          .text,
      'P002',
    );
    expect(find.text('新增成功'), findsOneWidget);
  });

  testWidgets('删除二次确认后清空结果但保留输入框', (tester) async {
    String? deletedNo;
    await _pumpWidget(
      tester,
      _app(
        onQuery: (_) async => _result(
          type: 'query',
          deviceNo: 'P001',
          data: _deviceData(deviceNo: 'P001'),
        ),
        onDelete: (no) async {
          deletedNo = no;
          return _result(type: 'delete', deviceNo: no);
        },
      ),
    );

    await _queryDevice(tester, 'P001');
    await tester.ensureVisible(find.byKey(const Key('online-delete')));
    await tester.tap(find.byKey(const Key('online-delete')));
    await tester.pump();
    expect(find.text('确认删除设备'), findsOneWidget);
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();

    expect(deletedNo, 'P001');
    expect(find.byKey(const Key('online-value-设备编号')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('online-device-no')))
          .controller!
          .text,
      'P001',
    );
    expect(find.text('删除成功'), findsOneWidget);
  });

  testWidgets('修改失败时编辑页保持打开', (tester) async {
    await _pumpWidget(
      tester,
      _app(
        onQuery: (_) async => _result(
          type: 'query',
          deviceNo: 'P001',
          data: _deviceData(deviceNo: 'P001'),
        ),
        onModify: (_, __) async => _result(
          type: 'modify',
          success: false,
          message: '设备不存在',
        ),
      ),
    );

    await _queryDevice(tester, 'P001');
    await tester.ensureVisible(find.byKey(const Key('online-edit')));
    await tester.tap(find.byKey(const Key('online-edit')));
    await tester.pumpAndSettle();
    await _saveEditor(tester);

    expect(find.byType(DeviceEditPage), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);
  });
}

/// 构造在线页测试所需的应用壳和可替换 API 回调。
Widget _app({
  Future<DeviceResult> Function(String)? onQuery,
  Future<DeviceResult> Function(String, Map<String, dynamic>)? onModify,
  Future<DeviceResult> Function(Map<String, dynamic>)? onAdd,
  Future<DeviceResult> Function(String)? onDelete,
}) {
  return MaterialApp(
    home: OnlinePage(
      onQuery: onQuery,
      onModify: onModify,
      onAdd: onAdd,
      onDelete: onDelete,
    ),
  );
}

/// 使用固定字段构造一整行在线设备数据。
Map<String, dynamic> _deviceData({required String deviceNo}) {
  return {
    for (final header in onlineDeviceHeaders)
      header: header == '设备编号' ? deviceNo : '$header-$deviceNo',
  };
}

/// 构造网络层返回的业务结果。
DeviceResult _result({
  required String type,
  bool success = true,
  String? deviceNo,
  Map<String, dynamic>? data,
  String? message,
}) {
  return DeviceResult.fromJson({
    'success': success,
    'type': type,
    if (deviceNo != null) 'device_no': deviceNo,
    if (data != null) 'data': data,
    if (message != null) 'message': message,
  });
}

/// 在测试中执行一次设备编号查询并等待页面完成刷新。
Future<void> _queryDevice(WidgetTester tester, String deviceNo) async {
  await tester.enterText(find.byKey(const Key('online-device-no')), deviceNo);
  await tester.tap(find.byKey(const Key('online-query')));
  await tester.pumpAndSettle();
}

/// 使用足够高的测试视口容纳共享编辑器的完整设备表单。
Future<void> _pumpWidget(WidgetTester tester, Widget child) async {
  tester.binding.window.physicalSizeTestValue = const Size(800, 1400);
  tester.binding.window.devicePixelRatioTestValue = 1;
  addTearDown(() {
    tester.binding.window.clearPhysicalSizeTestValue();
    tester.binding.window.clearDevicePixelRatioTestValue();
  });
  await tester.pumpWidget(child);
}

/// 滚动共享编辑器到保存按钮并提交当前表单。
Future<void> _saveEditor(WidgetTester tester) async {
  final saveButton = find.text('保存', skipOffstage: false);
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
}
