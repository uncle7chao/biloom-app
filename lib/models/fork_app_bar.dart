import 'package:flutter/widgets.dart';

/// fork 兼容：v0.9.2 上游把 AppBar 状态挪进 ui/models.dart（freezed），
/// fork 的 CommonScaffold 仍用这套旧结构，这里手写等价类避免 codegen。
class AppBarState {
  final List<Widget> actions;
  final AppBarSearchState? searchState;
  final AppBarEditState? editState;

  const AppBarState({
    this.actions = const [],
    this.searchState,
    this.editState,
  });

  AppBarState copyWith({
    List<Widget>? actions,
    AppBarSearchState? searchState,
    AppBarEditState? editState,
  }) =>
      AppBarState(
        actions: actions ?? this.actions,
        searchState: searchState ?? this.searchState,
        editState: editState ?? this.editState,
      );
}

class AppBarSearchState {
  final Function(String) onSearch;
  final bool autoAddSearch;
  final String? query;

  const AppBarSearchState({
    required this.onSearch,
    this.autoAddSearch = true,
    this.query,
  });

  AppBarSearchState copyWith({
    Function(String)? onSearch,
    bool? autoAddSearch,
    String? query,
  }) =>
      AppBarSearchState(
        onSearch: onSearch ?? this.onSearch,
        autoAddSearch: autoAddSearch ?? this.autoAddSearch,
        query: query ?? this.query,
      );
}

class AppBarEditState {
  final int editCount;
  final Function() onExit;

  const AppBarEditState({
    this.editCount = 0,
    required this.onExit,
  });

  AppBarEditState copyWith({
    int? editCount,
    Function()? onExit,
  }) =>
      AppBarEditState(
        editCount: editCount ?? this.editCount,
        onExit: onExit ?? this.onExit,
      );
}
