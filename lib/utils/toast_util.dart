import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ToastUtil {
  /// 底部提示
  static void showBottom(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      gravity: ToastGravity.BOTTOM,
      toastLength: Toast.LENGTH_SHORT,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  /// 中间提示
  static void showCenter(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      gravity: ToastGravity.CENTER,
      toastLength: Toast.LENGTH_SHORT,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  /// 顶部提示
  static void showTop(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      gravity: ToastGravity.TOP,
      toastLength: Toast.LENGTH_SHORT,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  /// 长时间底部提示
  static void showLongBottom(String msg) {
    Fluttertoast.showToast(
      msg: msg,
      gravity: ToastGravity.BOTTOM,
      toastLength: Toast.LENGTH_LONG,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }

  /// 自定义颜色和时长
  static void showCustom({
    required String msg,
    ToastGravity gravity = ToastGravity.BOTTOM,
    Color bgColor = Colors.black87,
    Color textColor = Colors.white,
    double fontSize = 14.0,
    bool isLong = false,
  }) {
    Fluttertoast.showToast(
      msg: msg,
      gravity: gravity,
      toastLength: isLong ? Toast.LENGTH_LONG : Toast.LENGTH_SHORT,
      backgroundColor: bgColor,
      textColor: textColor,
      fontSize: fontSize,
    );
  }
}
