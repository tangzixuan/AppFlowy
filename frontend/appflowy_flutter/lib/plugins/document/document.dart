library;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/document_page.dart';
import 'package:appflowy/plugins/document/presentation/document_collaborators.dart';
import 'package:appflowy/plugins/shared/share/share_button.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DocumentPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return DocumentPlugin(pluginType: pluginType, view: data);
    }

    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => LocaleKeys.document_menuName.tr();

  @override
  FlowySvgData get icon => FlowySvgs.icon_document_s;

  @override
  PluginType get pluginType => PluginType.document;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class DocumentPlugin extends Plugin {
  DocumentPlugin({
    required ViewPB view,
    required PluginType pluginType,
    this.initialSelection,
    this.initialBlockId,
  }) : notifier = ViewPluginNotifier(view: view) {
    _pluginType = pluginType;
  }

  late PluginType _pluginType;
  late final ViewInfoBloc _viewInfoBloc;
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  final ViewPluginNotifier notifier;

  // the initial selection of the document
  final Selection? initialSelection;

  // the initial block id of the document
  final String? initialBlockId;

  @override
  PluginWidgetBuilder get widgetBuilder => DocumentPluginWidgetBuilder(
        bloc: _viewInfoBloc,
        pageAccessLevelBloc: _pageAccessLevelBloc,
        notifier: notifier,
        initialSelection: initialSelection,
        initialBlockId: initialBlockId,
      );

  @override
  PluginType get pluginType => _pluginType;

  @override
  PluginId get id => notifier.view.id;

  @override
  void init() {
    _viewInfoBloc = ViewInfoBloc(view: notifier.view)
      ..add(const ViewInfoEvent.started());
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view)
      ..add(const PageAccessLevelEvent.initial());
  }

  @override
  void dispose() {
    _viewInfoBloc.close();
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

class DocumentPluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  DocumentPluginWidgetBuilder({
    required this.bloc,
    required this.notifier,
    this.initialSelection,
    this.initialBlockId,
    required this.pageAccessLevelBloc,
  });

  final ViewInfoBloc bloc;
  final ViewPluginNotifier notifier;
  final PageAccessLevelBloc pageAccessLevelBloc;

  ViewPB get view => notifier.view;
  int? deletedViewIndex;
  final Selection? initialSelection;
  final String? initialBlockId;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    notifier.isDeleted.addListener(() {
      final deletedView = notifier.isDeleted.value;
      if (deletedView != null && deletedView.hasIndex()) {
        deletedViewIndex = deletedView.index;
      }
    });

    final fixedTitle = data?[MobileDocumentScreen.viewFixedTitle];
    final blockId = initialBlockId ?? data?[MobileDocumentScreen.viewBlockId];
    final tabs = data?[MobileDocumentScreen.viewSelectTabs] ??
        const [
          PickerTabType.emoji,
          PickerTabType.icon,
          PickerTabType.custom,
        ];

    return MultiBlocProvider(
      providers: [
        BlocProvider<ViewInfoBloc>.value(
          value: bloc,
        ),
        BlocProvider<PageAccessLevelBloc>.value(
          value: pageAccessLevelBloc,
        ),
      ],
      child: BlocBuilder<DocumentAppearanceCubit, DocumentAppearance>(
        builder: (_, state) => DocumentPage(
          key: ValueKey(view.id),
          view: view,
          onDeleted: () => context.onDeleted?.call(view, deletedViewIndex),
          initialSelection: initialSelection,
          initialBlockId: blockId,
          fixedTitle: fixedTitle,
          tabs: tabs,
        ),
      ),
    );
  }

  @override
  String? get viewName => notifier.view.nameOrDefault;

  @override
  Widget get leftBarItem {
    return BlocProvider.value(
      value: pageAccessLevelBloc,
      child: ViewTitleBar(key: ValueKey(view.id), view: view),
    );
  }

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);

  @override
  Widget? get rightBarItem {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ViewInfoBloc>.value(
          value: bloc,
        ),
        BlocProvider<PageAccessLevelBloc>.value(
          value: pageAccessLevelBloc,
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...FeatureFlag.syncDocument.isOn
              ? [
                  DocumentCollaborators(
                    key: ValueKey('collaborators_${view.id}'),
                    width: 120,
                    height: 32,
                    view: view,
                  ),
                  const HSpace(16),
                ]
              : [const HSpace(8)],
          ShareButton(
            key: ValueKey('share_button_${view.id}'),
            view: view,
          ),
          const HSpace(10),
          ViewFavoriteButton(
            key: ValueKey('favorite_button_${view.id}'),
            view: view,
          ),
          const HSpace(4),
          MoreViewActions(view: view),
        ],
      ),
    );
  }

  @override
  List<NavigationItem> get navigationItems => [this];
}
