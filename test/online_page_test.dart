import 'package:excel_app/online/online_page.dart';
import 'package:excel_app/online/online_config_page.dart';
import 'package:excel_app/online/online_config_store.dart';
import 'package:excel_app/device_edit_page.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 验证在线设备页面的固定字段展示入口已经存在。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  _registerConfigTests();

  testWidgets('读取配置后仅显示 URL 对应的文件名', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'online_api_url': 'https://example.com/scripts/device_sync_task',
      'online_api_token': 'token-123',
    });

    await _pumpWidget(tester, _app());
    await tester.pumpAndSettle();

    expect(find.text('当前文件: device_sync_task'), findsOneWidget);
    expect(find.text('https://example.com/scripts/device_sync_task'),
        findsNothing);
    expect(find.widgetWithText(Text, 'token-123'), findsNothing);
  });

  testWidgets('拖动在线页面时隐藏键盘', (tester) async {
    await _pumpWidget(tester, _app());

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scrollView.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
  });

  testWidgets('点击在线页面非输入框时隐藏键盘', (tester) async {
    await _pumpWidget(tester, _app());
    final input = find.byKey(const Key('online-device-no'));

    await tester.tap(input);
    await tester.pump();
    expect(_inputHasFocus(tester, input), isTrue);

    await tester.tap(find.text('设备查询'));
    await tester.pump();
    expect(_inputHasFocus(tester, input), isFalse);
  });

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

    expect(find.byKey(const Key('online-column-部门')), findsOneWidget);
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

  testWidgets('使用脚本真实字段并完整传入编辑器', (tester) async {
    await _pumpWidget(
      tester,
      _app(
        onQuery: (_) async => _result(
          type: 'query',
          deviceNo: 'P001',
          data: _actualDeviceData(deviceNo: 'P001'),
        ),
      ),
    );

    await _queryDevice(tester, 'P001');
    expect(
      find.descendant(
        of: find.byKey(const Key('online-value-部门')),
        matching: find.text('质量管理部'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('online-value-状态')),
        matching: find.text('正常使用'),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byKey(const Key('online-edit')));
    await tester.tap(find.byKey(const Key('online-edit')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('field-部门')))
          .controller!
          .text,
      '质量管理部',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('field-仪器设备负责人')))
          .controller!
          .text,
      '韩爽',
    );
  });

  testWidgets('修改时直接使用脚本真实列名', (tester) async {
    Map<String, dynamic>? modifiedData;
    await _pumpWidget(
      tester,
      _app(
        onQuery: (_) async => _result(
          type: 'query',
          deviceNo: 'P001',
          data: _actualDeviceData(deviceNo: 'P001'),
        ),
        onModify: (_, data) async {
          modifiedData = data;
          return _result(
            type: 'modify',
            deviceNo: 'P001',
            data: _actualDeviceData(deviceNo: 'P001'),
          );
        },
      ),
    );

    await _queryDevice(tester, 'P001');
    await tester.ensureVisible(find.byKey(const Key('online-edit')));
    await tester.tap(find.byKey(const Key('online-edit')));
    await tester.pumpAndSettle();
    await _saveEditor(tester);

    expect(modifiedData?['部门'], '质量管理部');
    expect(modifiedData?['状态'], '正常使用');
    expect(modifiedData?['仪器设备负责人'], '韩爽');
    expect(modifiedData?.containsKey('归属部门'), isFalse);
    expect(modifiedData?.containsKey('设备状态'), isFalse);
    expect(modifiedData?.containsKey('设备负责人'), isFalse);
  });

  testWidgets('新增时使用脚本实际列名提交整行', (tester) async {
    Map<String, dynamic>? addedData;
    await _pumpWidget(
      tester,
      _app(
        onAdd: (data) async {
          addedData = data;
          return _result(
            type: 'add',
            deviceNo: 'P002',
            data: _actualDeviceData(deviceNo: 'P002'),
          );
        },
      ),
    );

    await tester.tap(find.byKey(const Key('online-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-设备编号')), 'P002');
    await _saveEditor(tester);

    expect(addedData?['设备编号'], 'P002');
    expect(addedData?['部门'], isEmpty);
    expect(addedData?['状态'], isEmpty);
    expect(addedData?['仪器设备负责人'], isEmpty);
    expect(addedData?.containsKey('归属部门'), isFalse);
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

/// 验证在线接口配置可以保存并显示 URL 对应的文件名。
void _registerConfigTests() {
  testWidgets('保存接口配置后显示 URL 文件名并可再次读取', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnlineConfigPage()));

    await tester.enterText(
      find.byKey(const Key('online-config-url')),
      'https://example.com/scripts/device_sync_task',
    );
    await tester.enterText(
      find.byKey(const Key('online-config-token')),
      'token-123',
    );
    await tester.tap(find.byKey(const Key('online-config-save')));
    await tester.pumpAndSettle();

    expect(find.text('当前文件: device_sync_task'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('online-config-token')))
          .obscureText,
      isTrue,
    );
    final savedConfig = await const OnlineConfigStore().load();
    expect(savedConfig?.url, 'https://example.com/scripts/device_sync_task');
    expect(savedConfig?.token, 'token-123');
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

/// 构造 WPS 表格脚本实际返回的列名和一整行设备数据。
Map<String, dynamic> _actualDeviceData({required String deviceNo}) {
  return {
    '部门': '质量管理部',
    '来源': '自购',
    '状态': '正常使用',
    '设备编号': deviceNo,
    '设备名称': '新飞牌冷藏冷冻箱',
    '设备型号': 'BCD-239V',
    '机身号': '/',
    '生产厂家': '河南新飞电器有限公司',
    '所在区域': 'PCR质检I区',
    '所在房间': '',
    '设备分类': '一般设备',
    '仪器设备负责人': '韩爽',
    '计量机构': '',
    '证书类型': '',
    '计量有效期至': '',
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

/// 返回指定文本框内部 EditableText 的实际焦点状态。
bool _inputHasFocus(WidgetTester tester, Finder textField) {
  final editableText = tester.widget<EditableText>(
    find.descendant(of: textField, matching: find.byType(EditableText)),
  );
  return editableText.focusNode.hasFocus;
}
