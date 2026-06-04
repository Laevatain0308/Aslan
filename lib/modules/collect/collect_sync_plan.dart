class CollectSyncPlan {
  const CollectSyncPlan({
    required this.webDavFeatureEnabled,
    required this.webDavEnabled,
    required this.webDavCollectiblesEnabled,
    required this.bangumiEnabled,
    this.privateSyncEnabled = false,
    this.privateSyncCollectiblesEnabled = false,
  });

  factory CollectSyncPlan.fromSettings({
    required bool webDavFeatureEnabled,
    required bool webDavEnabled,
    required bool webDavCollectiblesEnabled,
    required bool bangumiEnabled,
    required bool privateSyncEnabled,
    required bool privateSyncCollectiblesEnabled,
  }) {
    return CollectSyncPlan(
      webDavFeatureEnabled: webDavFeatureEnabled,
      webDavEnabled: webDavEnabled,
      webDavCollectiblesEnabled: webDavCollectiblesEnabled,
      bangumiEnabled: bangumiEnabled,
      privateSyncEnabled: privateSyncEnabled,
      privateSyncCollectiblesEnabled: privateSyncCollectiblesEnabled,
    );
  }

  final bool webDavFeatureEnabled;
  final bool webDavEnabled;
  final bool webDavCollectiblesEnabled;
  final bool bangumiEnabled;
  final bool privateSyncEnabled;
  final bool privateSyncCollectiblesEnabled;

  bool get shouldSyncWebDavCollectibles =>
      webDavFeatureEnabled && webDavEnabled && webDavCollectiblesEnabled;

  bool get shouldSyncBangumi => bangumiEnabled;

  bool get shouldSyncPrivateCollectibles =>
      privateSyncEnabled && privateSyncCollectiblesEnabled;

  bool get canSync =>
      shouldSyncWebDavCollectibles ||
      shouldSyncBangumi ||
      shouldSyncPrivateCollectibles;

  bool shouldUploadWebDavAfterBangumi({
    required bool webDavSynced,
    required bool bangumiSynced,
  }) {
    return shouldSyncWebDavCollectibles &&
        shouldSyncBangumi &&
        webDavSynced &&
        bangumiSynced;
  }
}
