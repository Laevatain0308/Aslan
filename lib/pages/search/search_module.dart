import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/pages/search/image_search_page.dart';
import 'package:kazumi/utils/app_feature_flags.dart';

class SearchModule extends Module {
  @override
  void binds(i) {}

  @override
  void routes(r) {
    if (AppFeatureFlags.imageSearch) {
      r.child("/image", child: (_) => const ImageSearchPage());
    }
    r.child("/:tag", child: (_) {
      return SearchPage(inputTag: r.args.params['tag']);
    });
  }
}
