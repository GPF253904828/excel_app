import 'dart:async';

import 'package:excel_app/device_detail_page.dart';
import 'package:excel_app/device_edit_page.dart';
import 'package:excel_app/online/online_config_page.dart';
import 'package:excel_app/online/online_config_store.dart';
import 'package:excel_app/online/online_page.dart';
import 'package:excel_app/qr_create_page.dart';
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

  test('接口返回字段按预设顺序排列且不补默认列', () {
    expect(
      onlineTableHeaders(<Map<String, dynamic>>[
        <String, dynamic>{
          '设备名称': '设备A',
          '设备负责人': '张三',
          '备注': '扩展字段',
          '归属部门': '设备部',
          '设备状态': '正常使用',
          '设备编号': 'P001',
        },
      ]),
      <String>[
        '归属部门',
        '设备状态',
        '设备编号',
        '设备名称',
        '设备负责人',
        '备注',
      ],
    );
  });

  test('详情数据按在线列表表头顺序排列', () {
    final data = <String, dynamic>{
      '设备名称': '设备A',
      '设备编号': 'P001',
      '归属部门': '设备部',
    };
    final headers = onlineTableHeaders(<Map<String, dynamic>>[data]);

    expect(orderedOnlineDeviceData(data, headers).keys.toList(), headers);
  });

  testWidgets('进入在线页后加载首页，按钮和下拉都会重新加载首页', (tester) async {
    final requestedStarts = <int>[];
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) async {
          requestedStarts.add(start);
          return _listResult(<Map<String, dynamic>>[
            _deviceRow(
              deviceNo:
                  start == 0 && requestedStarts.length == 1 ? 'P001' : 'P002',
              name: start == 0 && requestedStarts.length == 1 ? '设备A' : '设备B',
            ),
          ], total: 2, start: start, limit: limit);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedStarts, <int>[0]);
    expect(find.text('P001'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新列表'));
    await tester.pumpAndSettle();

    expect(requestedStarts, <int>[0, 0]);
    expect(find.text('P001'), findsNothing);
    expect(find.text('P002'), findsOneWidget);

    await tester.fling(
      find.byKey(const Key('spreadsheet-vertical-list')),
      const Offset(0, 500),
      1000,
    );
    await tester.pumpAndSettle();

    expect(requestedStarts, <int>[0, 0, 0]);
  });

  testWidgets('刷新首页时显示第一页加载状态', (tester) async {
    final refreshResult = Completer<DeviceListResult>();
    var listCalls = 0;
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) {
          listCalls++;
          if (listCalls == 1) {
            return Future<DeviceListResult>.value(
              _listResult(
                <Map<String, dynamic>>[
                  _deviceRow(deviceNo: 'P001', name: '设备A'),
                ],
                total: 2,
                start: start,
                limit: limit,
              ),
            );
          }
          return refreshResult.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('刷新列表'));
    await tester.pump();
    expect(find.text('正在加载第一页'), findsOneWidget);

    refreshResult.complete(
      _listResult(
        <Map<String, dynamic>>[
          _deviceRow(deviceNo: 'P002', name: '设备B'),
        ],
        total: 2,
        start: 0,
        limit: 50,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loading...'), findsNothing);
    expect(find.text('P002'), findsOneWidget);
  });

  testWidgets('加载下一页时显示第二页加载状态', (tester) async {
    final nextPage = Completer<DeviceListResult>();
    addTearDown(() {
      if (!nextPage.isCompleted) {
        nextPage.complete(
          _listResult(
            const <Map<String, dynamic>>[],
            total: 50,
            start: 53,
            limit: 50,
          ),
        );
      }
    });
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) {
          if (start == 53) return nextPage.future;
          return Future<DeviceListResult>.value(
            _listResult(
              _deviceRows('P', 50),
              total: 51,
              start: start,
              limit: limit,
              hasMore: true,
              nextStart: 53,
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('spreadsheet-vertical-list')),
      const Offset(0, -6000),
    );
    await tester.pump();
    expect(find.text('正在加载第2页'), findsOneWidget);

    nextPage.complete(
      _listResult(
        _deviceRows('P', 1, offset: 50),
        total: 51,
        start: 53,
        limit: 50,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('首页加载失败时显示接口错误', (tester) async {
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) async =>
            DeviceListResult.fromJson(<String, dynamic>{
          'success': false,
          'message': '接口不可用',
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('接口不可用'), findsOneWidget);
  });

  testWidgets('上拉按脚本 nextStart 加载下一页，并在末页显示加载完毕', (tester) async {
    final requestedStarts = <int>[];
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) async {
          requestedStarts.add(start);
          return start == 0
              ? _listResult(
                  _deviceRows('P', 50),
                  total: 51,
                  start: start,
                  limit: limit,
                  hasMore: true,
                  nextStart: 53,
                )
              : _listResult(
                  _deviceRows('P', 1, offset: 50),
                  total: 51,
                  start: start,
                  limit: limit,
                );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('spreadsheet-vertical-list')),
      const Offset(0, -6000),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('spreadsheet-vertical-list')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(requestedStarts, <int>[0, 53]);
    expect(find.text('加载完毕'), findsOneWidget);
    expect(find.text('已全部加载完成51条数据'), findsOneWidget);
  });

  testWidgets('滚动触底时立即加载下一页，不等待手势结束', (tester) async {
    final nextPage = Completer<DeviceListResult>();
    final requestedStarts = <int>[];
    addTearDown(() {
      if (!nextPage.isCompleted) {
        nextPage.complete(
          _listResult(
            const <Map<String, dynamic>>[],
            total: 50,
            start: 50,
            limit: 50,
          ),
        );
      }
    });
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) {
          requestedStarts.add(start);
          if (start == 50) return nextPage.future;
          return Future<DeviceListResult>.value(
            _listResult(
              _deviceRows('P', 50),
              total: 51,
              start: start,
              limit: limit,
              hasMore: true,
              nextStart: 50,
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('spreadsheet-vertical-list'));
    final gesture = await tester.startGesture(tester.getCenter(list));
    for (var index = 0; index < 6; index++) {
      await gesture.moveBy(const Offset(0, -1000));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(requestedStarts, <int>[0, 50]);
    await gesture.up();
  });

  testWidgets('恰好 50 条且 hasMore 为 false 时不再加载下一页', (tester) async {
    var listCalls = 0;
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) async {
          listCalls++;
          return _listResult(
            _deviceRows('P', 50),
            total: 50,
            start: start,
            limit: limit,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('spreadsheet-vertical-list')),
      const Offset(0, -6000),
    );
    await tester.pumpAndSettle();

    expect(listCalls, 1);
    expect(find.text('加载完毕'), findsOneWidget);
  });

  testWidgets('分页标题显示已加载数量和接口总数', (tester) async {
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) async => _listResult(
          _deviceRows('P', 50),
          total: 120,
          start: start,
          limit: limit,
          hasMore: true,
          nextStart: 50,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已加载50/120条数据'), findsOneWidget);
  });

  testWidgets('分页计数显示在 AppBar 的全宽底部区域', (tester) async {
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) async => _listResult(
          _deviceRows('P', 50),
          total: 120,
          start: start,
          limit: limit,
          hasMore: true,
          nextStart: 50,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(PreferredSize),
        matching: find.text('已加载50/120条数据'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('点击自动加载全部后按 nextStart 连续加载并显示状态', (tester) async {
    final requestedStarts = <int>[];
    final secondPage = Completer<DeviceListResult>();

    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) {
          requestedStarts.add(start);
          if (start == 0) {
            return Future<DeviceListResult>.value(
              _listResult(
                _deviceRows('P', 50),
                total: 120,
                start: 0,
                limit: limit,
                hasMore: true,
                nextStart: 50,
              ),
            );
          }
          return secondPage.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedStarts, <int>[0]);
    expect(find.byTooltip('自动加载全部'), findsOneWidget);
    expect(find.text('已加载50/120条数据'), findsOneWidget);

    await tester.tap(find.byTooltip('自动加载全部'));
    await tester.pump();

    expect(requestedStarts, <int>[0, 50]);
    expect(
      find.text('已加载50/120条数据，正在加载第2页'),
      findsOneWidget,
    );

    secondPage.complete(
      _listResult(
        _deviceRows('P', 70, offset: 50),
        total: 120,
        start: 50,
        limit: 70,
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedStarts, <int>[0, 50]);
    expect(find.text('已全部加载完成120条数据'), findsOneWidget);
  });

  testWidgets('自动加载分页失败后停止并保留已加载数据', (tester) async {
    final requestedStarts = <int>[];

    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) async {
          requestedStarts.add(start);
          if (start == 0) {
            return _listResult(
              _deviceRows('P', 50),
              total: 120,
              start: 0,
              limit: limit,
              hasMore: true,
              nextStart: 50,
            );
          }
          throw DeviceApiException('第二页加载失败');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('自动加载全部'));
    await tester.pumpAndSettle();

    expect(requestedStarts, <int>[0, 50]);
    expect(find.text('P000'), findsOneWidget);
    expect(find.textContaining('加载失败: 第二页加载失败'), findsOneWidget);
  });

  testWidgets('修改成功后更新本地行但不重新加载线上列表', (tester) async {
    var listCalls = 0;
    String? modifiedNo;
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) async {
          listCalls++;
          return _listResult(<Map<String, dynamic>>[
            _deviceRow(deviceNo: 'P001', name: '设备A'),
          ], total: 1, start: start, limit: limit);
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
    expect(listCalls, 1);
    expect(find.byType(DeviceEditPage), findsNothing);
    expect(find.text('编辑后设备'), findsOneWidget);
    expect(find.text('P001'), findsOneWidget);
  });

  testWidgets('新增和删除成功后更新本地列表但不重新加载', (tester) async {
    var listCalls = 0;
    await _pumpWidget(
      tester,
      _app(
        onList: ({required start, required limit}) async {
          listCalls++;
          return _listResult(<Map<String, dynamic>>[
            _deviceRow(deviceNo: 'P001', name: '设备A'),
          ], total: 1, start: start, limit: limit);
        },
        onAdd: (data) async {
          return _result(type: 'add', data: data);
        },
        onDelete: (deviceNo) async {
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

    expect(listCalls, 1);
    expect(find.text('设备A'), findsOneWidget);
    expect(find.text('设备B'), findsNothing);
  });

  testWidgets('确认切换配置后清空列表但不自动重新加载', (tester) async {
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
        onList: ({required start, required limit}) async {
          listCalls++;
          return _listResult(<Map<String, dynamic>>[
            _deviceRow(deviceNo: 'P001', name: '设备1'),
          ], total: 1, start: start, limit: limit);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('online-config')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('online-config-select-${custom.id}')));
    await tester.tap(find.byKey(const Key('online-config-confirm')));
    await tester.pumpAndSettle();

    expect(listCalls, 1);
    expect(find.text('暂无数据'), findsOneWidget);
  });

  testWidgets('read-only online list opens details without editing actions',
      (tester) async {
    await _pumpWidget(
      tester,
      _app(
        readOnly: true,
        onList: ({required start, required limit}) async => _listResult(
          <Map<String, dynamic>>[
            <String, dynamic>{
              '设备编号': 'P001',
              '设备名称': '设备A',
              '设备状态': '正常使用',
              '计量日期': '2026-09-01',
            },
          ],
          total: 1,
          start: start,
          limit: limit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('新增一行'), findsNothing);
    expect(find.byTooltip('生成二维码'), findsNothing);
    expect(find.byTooltip('扫码二维码'), findsNothing);
    await tester.tap(find.text('P001'));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceDetailPage), findsOneWidget);
    expect(find.text('2026-09-01'), findsOneWidget);
    expect(find.byType(DeviceEditPage), findsNothing);
  });

  testWidgets('read-only online list keeps QR export but hides API settings',
      (tester) async {
    await _pumpWidget(
      tester,
      _app(
        readOnly: true,
        qrExportPageBuilder: (archive, filename) => const Placeholder(),
        onList: ({required start, required limit}) async => _listResult(
          <Map<String, dynamic>>[
            _deviceRow(deviceNo: 'P001', name: '设备A'),
          ],
          total: 1,
          start: start,
          limit: limit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('online-config')), findsNothing);
    expect(find.byTooltip('刷新列表'), findsOneWidget);
    expect(find.byTooltip('生成二维码'), findsOneWidget);
  });

  testWidgets('前三次进入显示三个顶部按钮的操作引导', (tester) async {
    Future<DeviceListResult> list({required int start, required int limit}) =>
        Future<DeviceListResult>.value(
          _listResult(
            <Map<String, dynamic>>[
              _deviceRow(deviceNo: 'P001', name: '设备A'),
            ],
            total: 1,
            start: start,
            limit: limit,
          ),
        );

    for (var entry = 0; entry < 3; entry++) {
      await tester.pumpWidget(
        _app(
          onList: list,
          showOnboardingGuide: true,
          pageKey: UniqueKey(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump();

      final widgets = tester.allWidgets.toList();
      final textData =
          widgets.whereType<Text>().map((widget) => widget.data).toList();
      expect(textData.where((data) => data == '加载全部').length, 1);
      expect(
        textData.where((data) => data == '自动加载所有分页，不用再上拉加载更多。').length,
        1,
      );
      expect(textData.where((data) => data == '刷新').length, 1);
      expect(
        textData.where((data) => data == '清空当前列表，重新加载第一页。').length,
        1,
      );
      expect(textData.where((data) => data == '接口配置').length, 1);
      expect(
        textData.where((data) => data == '切换在线设备接口配置。').length,
        1,
      );
      expect(widgets.whereType<CustomPaint>(), isNotEmpty);

      await _tapGuideDismissButton(tester);
      await tester.pumpAndSettle();
      expect(
        tester.allWidgets.toList().whereType<Text>().any(
              (widget) => widget.data == '知道了',
            ),
        isFalse,
      );
    }

    await tester.pumpWidget(
      _app(
        onList: list,
        showOnboardingGuide: true,
        pageKey: UniqueKey(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.allWidgets.toList().whereType<Text>().any(
            (widget) => widget.data == '知道了',
          ),
      isFalse,
    );
  });

  testWidgets('只读在线设备页不显示三按钮操作引导', (tester) async {
    await _pumpWidget(
      tester,
      _app(
        readOnly: true,
        showOnboardingGuide: true,
        onList: ({required start, required limit}) async => _listResult(
          <Map<String, dynamic>>[
            _deviceRow(deviceNo: 'P001', name: '设备A'),
          ],
          total: 1,
          start: start,
          limit: limit,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.allWidgets.toList().whereType<Text>().any(
            (widget) => widget.data == '知道了',
          ),
      isFalse,
    );
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

  testWidgets('聚焦 Token 后取消新增配置不会使用已释放控制器', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnlineConfigPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('online-config-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('online-config-token')));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
  });

  test('配置弹窗控制器在路由移除后才释放', () async {
    final completed = Completer<void>();
    final controller = TextEditingController();

    final disposing = disposeConfigDialogControllersAfterRouteClosed(
      completed.future,
      <TextEditingController>[controller],
    );
    controller.text = '路由关闭前仍可编辑';
    expect(controller.text, '路由关闭前仍可编辑');

    completed.complete();
    await disposing;
    expect(
      () => controller.addListener(() {}),
      throwsA(isA<FlutterError>()),
    );
  });
}

/// 构造在线页测试所需的应用壳和可替换 API 回调。
Widget _app({
  DeviceListCallback? onList,
  Future<DeviceResult> Function(String, Map<String, dynamic>)? onModify,
  Future<DeviceResult> Function(Map<String, dynamic>)? onAdd,
  Future<DeviceResult> Function(String)? onDelete,
  OnlineConfigStore configStore = const OnlineConfigStore(),
  bool readOnly = false,
  QrExportPageBuilder? qrExportPageBuilder,
  bool showOnboardingGuide = false,
  Key? pageKey,
}) {
  return MaterialApp(
    home: OnlinePage(
      key: pageKey,
      onList: onList,
      onModify: onModify,
      onAdd: onAdd,
      onDelete: onDelete,
      configStore: configStore,
      readOnly: readOnly,
      qrExportPageBuilder: qrExportPageBuilder,
      showOnboardingGuide: showOnboardingGuide,
    ),
  );
}

/// 通过 OverlayEntry 中“知道了”按钮的 RenderBox 坐标触发点击。
Future<void> _tapGuideDismissButton(WidgetTester tester) async {
  final element = tester.allElements.firstWhere((element) {
    final widget = element.widget;
    return widget is FilledButton &&
        widget.child is Text &&
        (widget.child! as Text).data == '知道了';
  });
  final renderObject = element.renderObject;
  if (renderObject is! RenderBox) {
    throw StateError('引导关闭按钮没有可点击的 RenderBox');
  }
  final center = renderObject.localToGlobal(
    renderObject.size.center(Offset.zero),
  );
  await tester.tapAt(center);
}

/// 构造在线列表的一条设备记录。
Map<String, dynamic> _deviceRow({
  required String deviceNo,
  required String name,
}) =>
    <String, dynamic>{
      '归属部门': '设备部',
      '设备编号': deviceNo,
      '设备名称': name,
      '设备状态': '正常使用',
    };

/// 构造一页连续设备编号的模拟线上数据。
List<Map<String, dynamic>> _deviceRows(
  String prefix,
  int count, {
  int offset = 0,
}) =>
    <Map<String, dynamic>>[
      for (var index = 0; index < count; index++)
        _deviceRow(
          deviceNo: '$prefix${(offset + index).toString().padLeft(3, '0')}',
          name: '设备${offset + index}',
        ),
    ];

/// 构造网络层返回的一页列表业务结果。
DeviceListResult _listResult(
  List<Map<String, dynamic>> rows, {
  required int total,
  required int start,
  required int limit,
  bool hasMore = false,
  int? nextStart,
}) =>
    DeviceListResult.fromJson(<String, dynamic>{
      'success': true,
      'type': 'list',
      'total': total,
      'start': start,
      'limit': limit,
      'hasMore': hasMore,
      if (nextStart != null) 'nextStart': nextStart,
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
