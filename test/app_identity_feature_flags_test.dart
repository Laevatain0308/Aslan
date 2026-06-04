import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/app_feature_flags.dart';
import 'package:kazumi/utils/app_identity.dart';

void main() {
  test('public app identity is Aslan while retaining Kazumi attribution', () {
    expect(AppIdentity.name, 'Aslan');
    expect(AppIdentity.upstreamName, 'Kazumi');
    expect(AppIdentity.isOfficialUpstreamBuild, isFalse);
    expect(
        AppIdentity.upstreamRepository, 'https://github.com/Predidit/Kazumi');
  });

  test('unused upstream-backed features are hidden for Aslan builds', () {
    expect(AppFeatureFlags.danmaku, isFalse);
    expect(AppFeatureFlags.syncPlay, isFalse);
    expect(AppFeatureFlags.imageSearch, isFalse);
    expect(AppFeatureFlags.webDavSync, isFalse);
  });
}
