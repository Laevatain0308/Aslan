import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/storage/storage.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  final Box setting = GStorage.setting;
  late final TextEditingController serverController;

  @override
  void initState() {
    super.initState();
    serverController = TextEditingController(
      text: setting
          .get(
            SettingBoxKey.laevaBangumiServerUrl,
            defaultValue: ApiEndpoints.laevaBangumiDefaultApiBase,
          )
          .toString(),
    );
  }

  @override
  void dispose() {
    serverController.dispose();
    super.dispose();
  }

  Future<void> saveServerUrl() async {
    final value = serverController.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        uri.host.trim().isEmpty) {
      KazumiDialog.showToast(message: '服务器地址格式无效');
      return;
    }
    await setting.put(SettingBoxKey.laevaBangumiServerUrl, value);
    KazumiDialog.showToast(message: '服务器地址已保存');
  }

  Future<void> resetServerUrl() async {
    const value = ApiEndpoints.laevaBangumiDefaultApiBase;
    serverController.text = value;
    await setting.put(SettingBoxKey.laevaBangumiServerUrl, value);
    KazumiDialog.showToast(message: '已恢复默认服务器地址');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: Text('服务器地址')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: serverController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'LaevaBangumi API 地址',
              hintText: ApiEndpoints.laevaBangumiDefaultApiBase,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => saveServerUrl(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: resetServerUrl, child: const Text('恢复默认')),
              const SizedBox(width: 8),
              FilledButton(onPressed: saveServerUrl, child: const Text('保存')),
            ],
          ),
        ],
      ),
    );
  }
}
