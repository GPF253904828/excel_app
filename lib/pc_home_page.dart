import 'package:flutter/material.dart';

class PCHomePage extends StatelessWidget {
  const PCHomePage({super.key});

  Future<void> _onImport() async {
    // TODO: 实现导入逻辑
  }

  Future<void> _onExport() async {
    // TODO: 实现导出逻辑
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备管理')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 200,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _onImport,
                icon: const Icon(Icons.file_download),
                label: const Text('导入'),
              ),
            ),
            const SizedBox(height: 60),
            SizedBox(
              width: 200,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _onExport,
                icon: const Icon(Icons.file_upload),
                label: const Text('导出'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
