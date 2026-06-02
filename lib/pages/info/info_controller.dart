import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/laeva/laeva_bangumi_models.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/request/apis/laeva_bangumi_api.dart';
import 'package:mobx/mobx.dart';

part 'info_controller.g.dart';

class InfoController = _InfoController with _$InfoController;

abstract class _InfoController with Store {
  final CollectController collectController = Modular.get<CollectController>();
  late BangumiItem bangumiItem;

  LaevaBangumiDetail? laevaBangumiDetail;

  @observable
  bool isLoading = false;

  @observable
  var pluginSearchResponseList = ObservableList<PluginSearchResponse>();

  @observable
  var pluginSearchStatus = ObservableMap<String, String>();

  Future<void> queryLaevaBangumiInfo() async {
    isLoading = true;
    try {
      final id = LaevaBangumiMetadata.apiIdFromItem(bangumiItem);
      final detail = await LaevaBangumiApi.getDetail(id);
      if (detail == null) {
        return;
      }
      laevaBangumiDetail = detail;
      detail.applyToBangumiItem(bangumiItem);
      await collectController.updateLocalCollect(bangumiItem);
    } finally {
      isLoading = false;
    }
  }
}
