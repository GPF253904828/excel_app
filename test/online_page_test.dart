import 'package:excel_app/device_edit_page.dart';
import 'package:excel_app/online/online_config_page.dart';
import 'package:excel_app/online/online_config_store.dart';
import 'package:excel_app/online/online_page.dart';
import 'package:excel_app/utils/net_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 验证在线列表的加载、同步和配置切换流程。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  _registerConfigTests();

  test('标准字段固定在额外字段之前', () {
    expect(
      onlineTableHeaders(<Map<String, dynamic>>[
        <String, dynamic>{
          '设备名称': '设备A',
          '备注': '扩展字段',
          '设备编号': 'P001',
        },
      ]),
      <String>[...onlineDeviceHeaders, '备注'],
    );
  });

  testWidgets('进入在线页后立即加载全部设备列表', (tester) async {
    var listCalls = 0;
    await _pumpWidget(
      tester,
      _app(
        onList: () async {
          listCalls++;
          return _listResult(<Map<String, dynamic>>[
            _deviceRow(deviceNo: 'P001', name: '设备A'),
            _deviceRow(deviceNo: 'P002', name: '设备B'),
          ]);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(listCalls, 1);
    expect(find.text('P001'), findsOneWidget);
    expect(find.text('设备B'), findsOneWidget);
    expect(find.text('共 2 条数据'), findsOneWidget);
  });

  testWidgets('修改成功后重新加载线上列表', (tester) async {
    var listCalls = 0;
    String? modifiedNo;
    await _pumpWidget(
      tester,
      _app(
        onList: () async {
          listCalls++;
          return _listResult(<Map<String, dynamic>>[
            _deviceRow(
              deviceNo: listCalls == 1 ? 'P001' : 'P002',
              name: listCalls == 1 ? '设备A' : '线上同步后的设备',
            ),
          ]);
        },
        onModify: (deviceNo, data) async {
          modifiedNo = deviceNo;
          return _result(type: 'modify', deviceNo: deviceNo, data: data);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('设备A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-设备名称')), '编辑后设备');
    await _saveEditor(tester);

    expect(modifiedNo, 'P001');
    expect(listCalls, 2);
    expect(find.byType(DeviceEditPage), findsNothing);
    expect(find.text('线上同步后的设备'), findsOneWidget);
    expect(find.text('P001'), findsNothing);
  });

  testWidgets('新增和删除成功后都重新加载线上列表', (tester) async {
    var listCalls = 0;
    var added = false;
    var deleted = false;
    await _pumpWidget(
      tester,
      _app(
        onList: () async {
          listCalls++;
          if (!added) {
            return _listResult(<Map<String, dynamic>>[
              _deviceRow(deviceNo: 'P001', name: '设备A'),
            ]);
          }
          if (!deleted) {
            return _listResult(<Map<String, dynamic>>[
              _deviceRow(deviceNo: 'P002', name: '设备B'),
            ]);
          }
          return _listResult(const <Map<String, dynamic>>[]);
        },
        onAdd: (data) async {
          added = true;
          return _result(type: 'add', data: data);
        },
        onDelete: (deviceNo) async {
          deleted = true;
          return _result(type: 'delete', deviceNo: deviceNo);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新增一行'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('field-设备编号')), 'P002');
    await tester.enterText(find.byKey(const Key('field-设备名称')), '设备B');
    await _saveEditor(tester);
    expect(find.text('设备B'), findsOneWidget);

    await tester.longPress(find.text('设备B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(listCalls, 3);
    expect(find.text('暂无数据'), findsOneWidget);
  });

  testWidgets('确认切换配置后重新加载列表', (tester) async {
    const store = OnlineConfigStore();
    final custom = await store.create(
      url: 'https://example.com/sync',
      token: 'custom-token',
    );
    var listCalls = 0;
    await _pumpWidget(
      tester,
      _app(
        configStore: store,
        onList: () async {
          listCalls++;
          return _listResult(<Map<String, dynamic>>[
            _deviceRow(deviceNo: 'P00$listCalls', name: '设备$listCalls'),
          ]);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('online-config')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('online-config-select-${custom.id}')));
    await tester.tap(find.byKey(const Key('online-config-confirm')));
    await tester.pumpAndSettle();

    expect(listCalls, 2);
    expect(find.text('P002'), findsOneWidget);
  });
}

/// 验证在线接口配置列表的迁移、内置保护和选择流程。
void _registerConfigTests() {
  test('迁移旧配置并保护内置配置', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'online_api_url': 'https://legacy.example.com/sync',
      'online_api_token': 'legacy-token',
    });
    const store = OnlineConfigStore();

    final configs = await store.loadAll();
    final builtIn = configs.singleWhere((config) => config.isBuiltIn);
    final custom = configs.singleWhere((config) => !config.isBuiltIn);

    expect(builtIn.url, OnlineApiConfig.builtInUrl);
    expect(custom.url, 'https://legacy.example.com/sync');
    expect((await store.load())?.id, custom.id);
    await expectLater(store.delete(builtIn.id), throwsStateError);
  });

  test('自定义配置可以新增、修改和删除', () async {
    const store = OnlineConfigStore();
    final created = await store.create(
      url: 'https://example.com/first',
      token: 'first-token',
    );
    final updated = await store.update(
      created.copyWith(url: 'https://example.com/updated'),
    );

    expect(updated.url, 'https://example.com/updated');
    await store.delete(updated.id);
    expect(
      (await store.loadAll()).where((config) => config.id == updated.id),
      isEmpty,
    );
  });

  testWidgets('选择配置并确认后返回活动配置', (tester) async {
    const store = OnlineConfigStore();
    final custom = await store.create(
      url: 'https://example.com/sync',
      token: 'token-123',
    );
    OnlineApiConfig? returned;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              Navigator.push<OnlineApiConfig>(
                context,
                MaterialPageRoute(
                  builder: (_) => const OnlineConfigPage(store: store),
                ),
              ).then((config) => returned = config);
            },
            child: const Text('打开配置'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开配置'));
    await tester.pumpAndSettle();
    expect(find.text('内置'), findsOneWidget);
    expect(find.text('https://example.com/sync'), findsOneWidget);
    expect(
      find.byKey(const Key('online-config-edit-builtin')),
      findsNothing,
    );
    await tester.tap(find.byKey(Key('online-config-select-${custom.id}')));
    await tester.tap(find.byKey(const Key('online-config-confirm')));
    await tester.pumpAndSettle();

    expect(returned?.id, custom.id);
    expect((await store.load())?.id, custom.id);
  });

  testWidgets('新增和确认操作不会重叠', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnlineConfigPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('online-config-add')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byKey(const Key('online-config-confirm')), findsOneWidget);
  });
}

/// 构造在线页测试所需的应用壳和可替换 API 回调。
Widget _app({
  Future<DeviceListResult> Function()? onList,
  Future<DeviceResult> Function(String, Map<String, dynamic>)? onModify,
  Future<DeviceResult> Function(Map<String, dynamic>)? onAdd,
  Future<DeviceResult> Function(String)? onDelete,
  OnlineConfigStore configStore = const OnlineConfigStore(),
}) {
  return MaterialApp(
    home: OnlinePage(
      onList: onList,
      onModify: onModify,
      onAdd: onAdd,
      onDelete: onDelete,
      configStore: configStore,
    ),
  );
}

/// 构造在线列表的一条设备记录。
Map<String, dynamic> _deviceRow({
  required String deviceNo,
  required String name,
}) =>
    <String, dynamic>{
      '设备编号': deviceNo,
      '设备名称': name,
      '状态': '正常使用',
    };

/// 构造网络层返回的列表业务结果。
DeviceListResult _listResult(List<Map<String, dynamic>> rows) =>
    DeviceListResult.fromJson(<String, dynamic>{
      'success': true,
      'type': 'list',
      'rows': rows,
    });

/// 构造网络层返回的单行操作结果。
DeviceResult _result({
  required String type,
  String? deviceNo,
  Map<String, dynamic>? data,
}) =>
    DeviceResult.fromJson(<String, dynamic>{
      'success': true,
      'type': type,
      if (deviceNo != null) 'device_no': deviceNo,
      if (data != null) 'data': data,
    });

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
