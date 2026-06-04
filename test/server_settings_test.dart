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
}

TextField _textFieldByLabel(WidgetTester tester, String label) {
  return tester.widget<TextField>(
    find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    ),
  );
}
