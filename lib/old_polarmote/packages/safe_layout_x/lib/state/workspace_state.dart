class WorkspaceState {
  const WorkspaceState({this.openedTabs = const <String>[], this.activeTab});

  final List<String> openedTabs;
  final String? activeTab;

  WorkspaceState copyWith({
    List<String>? openedTabs,
    String? activeTab,
    bool clearActiveTab = false,
  }) {
    return WorkspaceState(
      openedTabs: openedTabs ?? this.openedTabs,
      activeTab: clearActiveTab ? null : (activeTab ?? this.activeTab),
    );
  }
}
