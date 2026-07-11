part of '../terminal_home_panels.dart';

class _LogPanel extends StatefulWidget {
  const _LogPanel({required this.appState});

  final TerminalAppState appState;

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final allItems = widget.appState.todayLogs.reversed.toList(growable: false);
    if (allItems.isEmpty) {
      return Center(
        child: Text(
          t(context, AppStrings.values.noLogs),
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }
    final items = _applyFilter(allItems);
    return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final inlineSearch = constraints.maxWidth >= 760;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l(
                                    widget.appState,
                                    AppStrings.values.todayVar,
                                    params: {'count': '${items.length}'},
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (inlineSearch) ...[
                                SizedBox(
                                  width: 280,
                                  height: 34,
                                  child: TextField(
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                      hintText: _searchHint(),
                                      prefixIcon: const Icon(
                                        Icons.search,
                                        size: 16,
                                      ),
                                      border: const OutlineInputBorder(),
                                    ),
                                    onChanged: (value) {
                                      if (!mounted) return;
                                      setState(() {
                                        _keyword = value;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              AppTextButton(
                                onPressed: widget.appState.openLogFolder,
                                icon: Icons.folder_open,
                                label: l(
                                  widget.appState,
                                  AppStrings.values.openFolder,
                                ),
                              ),
                            ],
                          ),
                          if (!inlineSearch) ...[
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 34,
                              child: TextField(
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                  hintText: _searchHint(),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 16,
                                  ),
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  if (!mounted) return;
                                  setState(() {
                                    _keyword = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  const SizedBox(height: 4),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        t(context, AppStrings.values.noLogs),
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                          children: _buildHighlightedLogSpans(items),
                        ),
                      ),
                    ),
            ),
          ],
        );
  }

  String _searchHint() {
    return l(widget.appState, AppStrings.values.logSearchHint);
  }

  List<InlineSpan> _buildHighlightedLogSpans(List<String> lines) {
    final keyword = _keyword.trim();
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      spans.addAll(_buildHighlightedLineSpans(lines[i], keyword));
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    return spans;
  }

  List<InlineSpan> _buildHighlightedLineSpans(String line, String keyword) {
    if (keyword.isEmpty) {
      return <InlineSpan>[TextSpan(text: line)];
    }
    final lowerLine = line.toLowerCase();
    final lowerKeyword = keyword.toLowerCase();
    final spans = <InlineSpan>[];
    var cursor = 0;
    while (true) {
      final matchIndex = lowerLine.indexOf(lowerKeyword, cursor);
      if (matchIndex < 0) {
        if (cursor < line.length) {
          spans.add(TextSpan(text: line.substring(cursor)));
        }
        break;
      }
      if (matchIndex > cursor) {
        spans.add(TextSpan(text: line.substring(cursor, matchIndex)));
      }
      final end = matchIndex + keyword.length;
      spans.add(
        TextSpan(
          text: line.substring(matchIndex, end),
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      cursor = end;
    }
    return spans;
  }

  List<String> _applyFilter(List<String> items) {
    final normalizedKeyword = _keyword.trim().toLowerCase();
    return items
        .where((line) {
          if (normalizedKeyword.isNotEmpty &&
              !line.toLowerCase().contains(normalizedKeyword)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

}
