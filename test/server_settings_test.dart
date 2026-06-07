import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/settings/server_settings.dart';

void main() {
  group('PrivateSyncAccountSettingsSection', () {
    late TextEditingController loginNameController;
    late TextEditingController displayNameController;
    late TextEditingController passwordController;
    late TextEditingController inviteCodeController;
    late TextEditingController tokenController;

    setUp(() {
      loginNameController = TextEditingController(text: 'alice');
      displayNameController = TextEditingController(text: 'Alice');
      passwordController = TextEditingController();
      inviteCodeController = TextEditingController();
      tokenController = TextEditingController();
    });

    tearDown(() {
      loginNameController.dispose();
      displayNameController.dispose();
      passwordController.dispose();
      inviteCodeController.dispose();
      tokenController.dispose();
    });

    testWidgets('shows credential form before login and keeps token read-only',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivateSyncAccountSettingsSection(
              isLoggedIn: false,
              displayName: '',
              authBusy: false,
              authRegistering: false,
              syncing: false,
              loginNameController: loginNameController,
              displayNameController: displayNameController,
              passwordController: passwordController,
              inviteCodeController: inviteCodeController,
              tokenController: tokenController,
              onLogin: () {},
              onRegister: () {},
              onLogout: () {},
            ),
          ),
        ),
      );

      expect(find.text('同步账号'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('邀请码'), findsOneWidget);
      expect(_textFieldByLabel(tester, '同步密钥').readOnly, isTrue);
    });

    testWidgets('hides credential form after login and keeps token read-only',
        (tester) async {
      tokenController.text = 'lbst_token';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivateSyncAccountSettingsSection(
              isLoggedIn: true,
              displayName: 'Alice',
              authBusy: false,
              authRegistering: false,
              syncing: false,
              loginNameController: loginNameController,
              displayNameController: displayNameController,
              passwordController: passwordController,
              inviteCodeController: inviteCodeController,
              tokenController: tokenController,
              onLogin: () {},
              onRegister: () {},
              onLogout: () {},
            ),
          ),
        ),
      );

      expect(find.text('已登录：Alice'), findsOneWidget);
      expect(find.text('同步账号'), findsNothing);
      expect(find.text('密码'), findsNothing);
      expect(find.text('邀请码'), findsNothing);
      expect(_textFieldByLabel(tester, '同步密钥').readOnly, isTrue);
    });

    testWidgets(
        'shows logout row after login even when display name is missing',
        (tester) async {
      tokenController.text = 'lbst_token';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivateSyncAccountSettingsSection(
              isLoggedIn: true,
              displayName: '',
              authBusy: false,
              authRegistering: false,
              syncing: false,
              loginNameController: loginNameController,
              displayNameController: displayNameController,
              passwordController: passwordController,
              inviteCodeController: inviteCodeController,
              tokenController: tokenController,
              onLogin: () {},
              onRegister: () {},
              onLogout: () {},
            ),
          ),
        ),
      );

      expect(find.text('已登录同步账号'), findsOneWidget);
      expect(find.text('退出'), findsOneWidget);
      expect(find.text('同步账号'), findsNothing);
      expect(find.text('密码'), findsNothing);
      expect(find.text('邀请码'), findsNothing);
      expect(_textFieldByLabel(tester, '同步密钥').readOnly, isTrue);
    });
  });

  group('ServerSettingsPage sync actions', () {
    testWidgets('shows SyncPlay server input with service field styling',
        (tester) async {
      final controller = TextEditingController(text: 'sync.example:8999');
      var saved = false;
      var reset = false;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SyncPlayServerSettingsSection(
              controller: controller,
              onSave: () {
                saved = true;
              },
              onReset: () {
                reset = true;
              },
            ),
          ),
        ),
      );

      final field = _textFieldByLabel(tester, 'SyncPlay 服务器');
      expect(field.controller, controller);
      expect(field.keyboardType, TextInputType.url);
      expect(field.decoration?.hintText, '默认 syncplay.pl:8996，格式 host:port');
      expect(field.decoration?.border, isA<OutlineInputBorder>());

      await tester.tap(find.text('保存'));
      await tester.tap(find.text('恢复默认'));

      expect(saved, isTrue);
      expect(reset, isTrue);
    });

    testWidgets('disables immediate sync when logged out', (tester) async {
      await tester.pumpWidget(
        _actionButtons(
          canTestConnection: false,
          canSyncNow: false,
        ),
      );

      final syncButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('立即同步'),
          matching: find.byType(FilledButton),
        ),
      );

      expect(syncButton.onPressed, isNull);
    });

    testWidgets('disables immediate sync when sync switch is off',
        (tester) async {
      await tester.pumpWidget(
        _actionButtons(
          canTestConnection: true,
          canSyncNow: false,
        ),
      );

      final syncButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('立即同步'),
          matching: find.byType(FilledButton),
        ),
      );

      expect(syncButton.onPressed, isNull);
    });

    testWidgets('enables immediate sync only when logged in and sync is on',
        (tester) async {
      var synced = false;
      await tester.pumpWidget(
        _actionButtons(
          canTestConnection: true,
          canSyncNow: true,
          onSyncNow: () {
            synced = true;
          },
        ),
      );

      await tester.tap(find.text('立即同步'));

      expect(synced, isTrue);
    });
  });
}

Widget _actionButtons({
  required bool canTestConnection,
  required bool canSyncNow,
  VoidCallback? onSyncNow,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PrivateSyncActionButtons(
        syncing: false,
        canTestConnection: canTestConnection,
        canSyncNow: canSyncNow,
        onTestConnection: () {},
        onSave: () {},
        onSyncNow: onSyncNow ?? () {},
      ),
    ),
  );
}

TextField _textFieldByLabel(WidgetTester tester, String label) {
  return tester.widget<TextField>(
    find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    ),
  );
}
