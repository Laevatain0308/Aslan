import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';

class BangumiEditorPage extends StatelessWidget {
  const BangumiEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: SysAppBar(title: Text('远程同步配置')),
      body: Center(child: Text('远程追番同步暂未开放')),
    );
  }
}
