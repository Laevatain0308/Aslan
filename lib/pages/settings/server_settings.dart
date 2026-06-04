import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/request/apis/private_sync_api.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/private_sync_service.dart';

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  final Box setting = GStorage.setting;
  late final TextEditingController serverController;
  late final TextEditingController tokenController;
  late final TextEditingController deviceNameController;
  late final TextEditingController loginNameController;
  late final TextEditingController displayNameController;
  late final TextEditingController passwordController;
  late final TextEditingController inviteCodeController;
  bool privateSyncEnable = false;
  bool privateSyncEnableWatch = true;
  bool privateSyncEnableCollect = true;
  bool syncing = false;
  bool authBusy = false;
  bool authRegistering = false;
  String syncDisplayName = '';

  bool get isSyncAccountLoggedIn => tokenController.text.trim().isNotEmpty;
  bool get isPrivateSyncPersistedEnabled =>
      setting.get(SettingBoxKey.privateSyncEnable, defaultValue: false) == true;
  PrivateSyncEnableState get privateSyncEnableState => PrivateSyncEnableState(
        persistedSyncEnabled: isPrivateSyncPersistedEnabled,
        persistedWatchEnabled: setting.get(SettingBoxKey.privateSyncEnableWatch,
                defaultValue: true) ==
            true,
        persistedCollectEnabled: setting.get(
                SettingBoxKey.privateSyncEnableCollect,
                defaultValue: true) ==
            true,
        nextSyncEnabled: privateSyncEnable,
        nextWatchEnabled: privateSyncEnableWatch,
        nextCollectEnabled: privateSyncEnableCollect,
      );

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
    tokenController = TextEditingController(
      text: setting.get(SettingBoxKey.privateSyncToken, defaultValue: ''),
    );
    deviceNameController = TextEditingController(
      text: setting.get(SettingBoxKey.privateSyncDeviceName, defaultValue: ''),
    );
    loginNameController = TextEditingController(
      text: setting.get(SettingBoxKey.privateSyncLoginName, defaultValue: ''),
    );
    displayNameController = TextEditingController(
      text: setting.get(SettingBoxKey.privateSyncDisplayName, defaultValue: ''),
    );
    passwordController = TextEditingController();
    inviteCodeController = TextEditingController();
    syncDisplayName = setting
        .get(SettingBoxKey.privateSyncDisplayName, defaultValue: '')
        .toString();
    privateSyncEnable = setting.get(
          SettingBoxKey.privateSyncEnable,
          defaultValue: false,
        ) ==
        true;
    privateSyncEnableWatch = setting.get(
          SettingBoxKey.privateSyncEnableWatch,
          defaultValue: true,
        ) ==
        true;
    privateSyncEnableCollect = setting.get(
          SettingBoxKey.privateSyncEnableCollect,
          defaultValue: true,
        ) ==
        true;
  }

  @override
  void dispose() {
    serverController.dispose();
    tokenController.dispose();
    deviceNameController.dispose();
    loginNameController.dispose();
    displayNameController.dispose();
    passwordController.dispose();
    inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> saveServerUrl() async {
    final value = serverController.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        uri.host.trim().isEmpty) {
      KazumiDialog.showToast(message: '服务地址格式无效');
      return;
    }
    await setting.put(SettingBoxKey.laevaBangumiServerUrl, value);
    KazumiDialog.showToast(message: '服务地址已保存');
  }

  Future<bool> savePrivateSyncSettings({bool showToast = true}) async {
    final token = tokenController.text.trim();
    if (privateSyncEnable && token.isEmpty) {
      KazumiDialog.showToast(message: '请先填写同步密钥');
      return false;
    }
    await setting.put(SettingBoxKey.privateSyncEnable, privateSyncEnable);
    await setting.put(SettingBoxKey.privateSyncToken, token);
    await setting.put(
      SettingBoxKey.privateSyncDeviceName,
      deviceNameController.text.trim(),
    );
    await setting.put(
      SettingBoxKey.privateSyncEnableWatch,
      privateSyncEnableWatch,
    );
    await setting.put(
      SettingBoxKey.privateSyncEnableCollect,
      privateSyncEnableCollect,
    );
    if (showToast) {
      KazumiDialog.showToast(message: '数据同步设置已保存');
    }
    return true;
  }

  Future<PrivateSyncEnableStrategy?> chooseEnableStrategy() async {
    if (!mounted) {
      return PrivateSyncEnableStrategy.merge;
    }
    return showDialog<PrivateSyncEnableStrategy>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('选择本次同步方式'),
          content: const Text('开启同步前，请选择如何处理当前设备与云端的数据。'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, PrivateSyncEnableStrategy.cloudFirst),
              child: const Text('使用云端'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, PrivateSyncEnableStrategy.merge),
              child: const Text('合并'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, PrivateSyncEnableStrategy.localFirst),
              child: const Text('上传本机'),
            ),
          ],
        );
      },
    );
  }

  Future<PrivateSyncEnableStrategy?> preparePrivateSyncEnableStrategy() async {
    if (!privateSyncEnableState.requiresEnableStrategy) {
      return PrivateSyncEnableStrategy.merge;
    }
    return chooseEnableStrategy();
  }

  void restorePersistedSyncSwitches() {
    privateSyncEnable = isPrivateSyncPersistedEnabled;
    privateSyncEnableWatch = setting.get(
          SettingBoxKey.privateSyncEnableWatch,
          defaultValue: true,
        ) ==
        true;
    privateSyncEnableCollect = setting.get(
          SettingBoxKey.privateSyncEnableCollect,
          defaultValue: true,
        ) ==
        true;
  }

  Future<void> loginSyncAccount() async {
    await authenticateSyncAccount(register: false);
  }

  Future<void> registerSyncAccount() async {
    await authenticateSyncAccount(register: true);
  }

  Future<void> authenticateSyncAccount({required bool register}) async {
    if (!await saveServerUrlIfValid()) {
      return;
    }
    final loginName = loginNameController.text.trim();
    final displayName = displayNameController.text.trim();
    final password = passwordController.text;
    final inviteCode = inviteCodeController.text.trim();
    if (loginName.isEmpty || password.isEmpty) {
      KazumiDialog.showToast(message: '请填写账号和密码');
      return;
    }
    if (register && (displayName.isEmpty || inviteCode.isEmpty)) {
      KazumiDialog.showToast(message: '请填写昵称和邀请码');
      return;
    }
    setState(() {
      authBusy = true;
      authRegistering = register;
    });
    try {
      final localStore = PrivateSyncLocalStore();
      final deviceId = await localStore.getDeviceId();
      final deviceName = privateSyncDeviceName();
      final api = PrivateSyncApi(token: tokenController.text.trim());
      final result = register
          ? await api.registerAccount(
              loginName: loginName,
              displayName: displayName,
              password: password,
              inviteCode: inviteCode,
              deviceId: deviceId,
              deviceName: deviceName,
              platform: Platform.operatingSystem,
              appVersion: ApiEndpoints.version,
            )
          : await api.login(
              loginName: loginName,
              password: password,
              deviceId: deviceId,
              deviceName: deviceName,
              platform: Platform.operatingSystem,
              appVersion: ApiEndpoints.version,
            );
      final previousLoginName = setting
          .get(SettingBoxKey.privateSyncLoginName, defaultValue: '')
          .toString();
      final previousToken = setting
          .get(SettingBoxKey.privateSyncToken, defaultValue: '')
          .toString();
      final strategy = await chooseEnableStrategy();
      await applySyncAuthResult(
        result,
        loginName: loginName,
        previousLoginName: previousLoginName,
        previousToken: previousToken,
        localStore: localStore,
        enableSync: strategy != null,
      );
      passwordController.clear();
      if (register) {
        inviteCodeController.clear();
      }
      KazumiDialog.showToast(
        message: strategy == null
            ? (register ? '同步账号已创建，数据同步未开启' : '同步账号已登录，数据同步未开启')
            : (register ? '同步账号已创建并登录' : '同步账号已登录'),
      );
      if (strategy != null) {
        await syncPrivateNow(strategy: strategy, forceLocalSnapshot: true);
      }
    } catch (e) {
      KazumiDialog.showToast(message: register ? '创建失败：$e' : '登录失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          authBusy = false;
          authRegistering = false;
        });
      }
    }
  }

  Future<void> applySyncAuthResult(
    PrivateSyncAuthResult result, {
    required String loginName,
    required String previousLoginName,
    required String previousToken,
    required PrivateSyncLocalStore localStore,
    required bool enableSync,
  }) async {
    await PrivateSyncService.saveAuthenticationResult(
      settings: const HivePrivateSyncSettingsStore(),
      localStore: localStore,
      result: result,
      loginName: loginName,
      previousLoginName: previousLoginName,
      previousToken: previousToken,
      deviceName: deviceNameController.text.trim(),
      enableSync: enableSync,
    );
    tokenController.text = result.token;
    if (result.displayName.isNotEmpty) {
      displayNameController.text = result.displayName;
    }
    privateSyncEnable = enableSync;
    if (mounted) {
      setState(() {
        syncDisplayName = result.displayName;
        privateSyncEnable = enableSync;
        privateSyncEnableWatch = true;
        privateSyncEnableCollect = true;
      });
    }
  }

  Future<void> logoutSyncAccount() async {
    final token = tokenController.text.trim();
    var revokeFailed = false;
    if (token.isNotEmpty) {
      try {
        await PrivateSyncApi(token: token).logout();
      } catch (_) {
        revokeFailed = true;
      }
    }
    await setting.put(SettingBoxKey.privateSyncEnable, false);
    await setting.put(SettingBoxKey.privateSyncToken, '');
    await setting.put(SettingBoxKey.privateSyncLoginName, '');
    await setting.put(SettingBoxKey.privateSyncDisplayName, '');
    await setting.put(SettingBoxKey.privateSyncWatchImported, false);
    await setting.put(SettingBoxKey.privateSyncCollectImported, false);
    await setting.put(SettingBoxKey.privateSyncWatchBaseline, '');
    await setting.put(SettingBoxKey.privateSyncCollectBaseline, '');
    await setting.put(
      SettingBoxKey.privateSyncPendingLocalOverrideWatch,
      false,
    );
    await setting.put(
      SettingBoxKey.privateSyncPendingLocalOverrideCollect,
      false,
    );
    await PrivateSyncLocalStore().clearEvents();
    tokenController.clear();
    loginNameController.clear();
    displayNameController.clear();
    passwordController.clear();
    inviteCodeController.clear();
    if (mounted) {
      setState(() {
        privateSyncEnable = false;
        syncDisplayName = '';
      });
    }
    KazumiDialog.showToast(
      message: revokeFailed ? '已退出同步账号，请稍后在其他设备重新登录' : '已退出同步账号',
    );
  }

  Future<void> handleSyncAuthenticationExpired() async {
    await PrivateSyncService.markAuthenticationExpired(
      const HivePrivateSyncSettingsStore(),
    );
    tokenController.clear();
    displayNameController.clear();
    passwordController.clear();
    inviteCodeController.clear();
    if (mounted) {
      setState(() {
        privateSyncEnable = false;
        syncDisplayName = '';
      });
    }
  }

  Future<bool> saveServerUrlIfValid() async {
    final value = serverController.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        uri == null ||
        !uri.hasScheme ||
        uri.host.trim().isEmpty) {
      KazumiDialog.showToast(message: '服务地址格式无效');
      return false;
    }
    await setting.put(SettingBoxKey.laevaBangumiServerUrl, value);
    return true;
  }

  Future<void> resetServerUrl() async {
    serverController.clear();
    await setting.delete(SettingBoxKey.laevaBangumiServerUrl);
    KazumiDialog.showToast(message: '已清除服务地址');
  }

  String privateSyncDeviceName() {
    final configured = deviceNameController.text.trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    return Platform.localHostname;
  }

  Future<void> testPrivateSyncStatus() async {
    if (!await savePrivateSyncSettings(showToast: false)) {
      return;
    }
    setState(() {
      syncing = true;
    });
    try {
      final status = await PrivateSyncApi().status();
      KazumiDialog.showToast(
        message:
            '连接成功：${status.displayName}，观看 ${status.watchHistoryCount}，收藏 ${status.collectionCount}',
      );
    } on PrivateSyncAuthenticationException {
      await handleSyncAuthenticationExpired();
      KazumiDialog.showToast(message: '同步账号已失效，请重新登录');
    } catch (e) {
      KazumiDialog.showToast(message: '连接失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          syncing = false;
        });
      }
    }
  }

  Future<void> syncPrivateNow({
    PrivateSyncEnableStrategy? strategy,
    bool? forceLocalSnapshot,
    bool? forceWatchSnapshot,
    bool? forceCollectionSnapshot,
  }) async {
    final enableState = privateSyncEnableState;
    final shouldForceLocalSnapshot =
        forceLocalSnapshot ?? enableState.requiresEnableStrategy;
    final shouldForceWatchSnapshot = forceWatchSnapshot ??
        (enableState.requiresEnableStrategy
            ? enableState.newlyEnabledWatch
            : null);
    final shouldForceCollectionSnapshot = forceCollectionSnapshot ??
        (enableState.requiresEnableStrategy
            ? enableState.newlyEnabledCollect
            : null);
    final selectedStrategy =
        strategy ?? await preparePrivateSyncEnableStrategy();
    if (selectedStrategy == null) {
      if (mounted) {
        setState(() {
          restorePersistedSyncSwitches();
        });
      }
      return;
    }
    if (!await savePrivateSyncSettings(showToast: false)) {
      return;
    }
    setState(() {
      syncing = true;
    });
    try {
      final service = PrivateSyncService();
      final result = await service.syncNowWithStrategy(
        selectedStrategy,
        forceLocalSnapshot: shouldForceLocalSnapshot,
        forceWatchSnapshot: shouldForceWatchSnapshot,
        forceCollectionSnapshot: shouldForceCollectionSnapshot,
      );
      refreshLocalControllers();
      KazumiDialog.showToast(
        message:
            '同步完成：上传 ${result.uploadedEventCount}，待同步 ${result.remainingEventCount}',
      );
    } on PrivateSyncAuthenticationException {
      await handleSyncAuthenticationExpired();
      KazumiDialog.showToast(message: '同步账号已失效，请重新登录');
    } catch (e) {
      KazumiDialog.showToast(message: '同步失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          syncing = false;
        });
      }
    }
  }

  void refreshLocalControllers() {
    try {
      Modular.get<HistoryController>().init();
    } catch (_) {}
    try {
      Modular.get<CollectController>().loadCollectibles();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(title: Text('服务与同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: serverController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '服务地址',
              hintText: '请输入兼容的服务 API 地址',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => saveServerUrl(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: resetServerUrl, child: const Text('清除')),
              const SizedBox(width: 8),
              FilledButton(onPressed: saveServerUrl, child: const Text('保存')),
            ],
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: privateSyncEnable,
            onChanged: (value) {
              setState(() {
                privateSyncEnable = value;
              });
            },
            title: const Text('数据同步'),
            subtitle: const Text('同步观看记录与追番状态'),
          ),
          const SizedBox(height: 12),
          PrivateSyncAccountSettingsSection(
            isLoggedIn: isSyncAccountLoggedIn,
            displayName: syncDisplayName,
            authBusy: authBusy,
            authRegistering: authRegistering,
            syncing: syncing,
            loginNameController: loginNameController,
            displayNameController: displayNameController,
            passwordController: passwordController,
            inviteCodeController: inviteCodeController,
            tokenController: tokenController,
            onLogin: loginSyncAccount,
            onRegister: registerSyncAccount,
            onLogout: logoutSyncAccount,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: deviceNameController,
            decoration: const InputDecoration(
              labelText: '设备名称',
              hintText: '留空时使用系统设备名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: privateSyncEnableWatch,
            onChanged: (value) {
              setState(() {
                privateSyncEnableWatch = value ?? true;
              });
            },
            title: const Text('同步观看记录'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: privateSyncEnableCollect,
            onChanged: (value) {
              setState(() {
                privateSyncEnableCollect = value ?? true;
              });
            },
            title: const Text('同步追番状态'),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: syncing ? null : testPrivateSyncStatus,
                icon: const Icon(Icons.cloud_done_rounded),
                label: const Text('测试连接'),
              ),
              OutlinedButton.icon(
                onPressed: syncing
                    ? null
                    : () async {
                        final enablingNow =
                            privateSyncEnableState.requiresEnableStrategy;
                        final forceWatchSnapshot =
                            privateSyncEnableState.newlyEnabledWatch;
                        final forceCollectionSnapshot =
                            privateSyncEnableState.newlyEnabledCollect;
                        final strategy =
                            await preparePrivateSyncEnableStrategy();
                        if (strategy == null) {
                          setState(() {
                            restorePersistedSyncSwitches();
                          });
                          return;
                        }
                        if (!await savePrivateSyncSettings(
                            showToast: !privateSyncEnable)) {
                          return;
                        }
                        if (privateSyncEnable) {
                          await syncPrivateNow(
                            strategy: strategy,
                            forceLocalSnapshot: enablingNow,
                            forceWatchSnapshot: forceWatchSnapshot,
                            forceCollectionSnapshot: forceCollectionSnapshot,
                          );
                        }
                      },
                icon: const Icon(Icons.save_rounded),
                label: const Text('保存同步设置'),
              ),
              FilledButton.icon(
                onPressed: syncing ? null : () => syncPrivateNow(),
                icon: syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: const Text('立即同步'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PrivateSyncAccountSettingsSection extends StatelessWidget {
  const PrivateSyncAccountSettingsSection({
    super.key,
    required this.isLoggedIn,
    required this.displayName,
    required this.authBusy,
    required this.authRegistering,
    required this.syncing,
    required this.loginNameController,
    required this.displayNameController,
    required this.passwordController,
    required this.inviteCodeController,
    required this.tokenController,
    required this.onLogin,
    required this.onRegister,
    required this.onLogout,
  });

  final bool isLoggedIn;
  final String displayName;
  final bool authBusy;
  final bool authRegistering;
  final bool syncing;
  final TextEditingController loginNameController;
  final TextEditingController displayNameController;
  final TextEditingController passwordController;
  final TextEditingController inviteCodeController;
  final TextEditingController tokenController;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final loggedInDisplayName = displayName.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLoggedIn)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified_user_rounded),
            title: Text(
              loggedInDisplayName.isEmpty
                  ? '已登录同步账号'
                  : '已登录：$loggedInDisplayName',
            ),
            subtitle: Text(
              loginNameController.text.trim().isEmpty
                  ? '同步账号已保存'
                  : loginNameController.text.trim(),
            ),
            trailing: TextButton(
              onPressed: authBusy || syncing ? null : onLogout,
              child: const Text('退出'),
            ),
          ),
        if (!isLoggedIn) ...[
          TextField(
            controller: loginNameController,
            decoration: const InputDecoration(
              labelText: '同步账号',
              hintText: '在不同设备上使用同一账号登录',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码',
              hintText: '至少 8 位',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: displayNameController,
            decoration: const InputDecoration(
              labelText: '昵称',
              hintText: '创建账号时显示在同步状态中',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: inviteCodeController,
            decoration: const InputDecoration(
              labelText: '邀请码',
              hintText: '创建账号时填写',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: authBusy || syncing ? null : onLogin,
                icon: authBusy && !authRegistering
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded),
                label: const Text('登录'),
              ),
              FilledButton.icon(
                onPressed: authBusy || syncing ? null : onRegister,
                icon: authBusy && authRegistering
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('创建账号'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: tokenController,
          obscureText: true,
          readOnly: true,
          enableInteractiveSelection: false,
          decoration: const InputDecoration(
            labelText: '同步密钥',
            hintText: '登录后自动保存',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
