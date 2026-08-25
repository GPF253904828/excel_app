import 'package:excel_app/home_page.dart';
import 'package:excel_app/pc_home_page.dart';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;

bool get isMobile => Platform.isAndroid || Platform.isIOS;
bool get isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: isDesktop ? const PCHomePage() : const HomePage(),
    );
  }
}
