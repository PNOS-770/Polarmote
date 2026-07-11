import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../../../shared/constants/app_string.dart';
import '../../state/terminal_app_state.dart';
import '../common/terminal_localization.dart';
import 'modal_panel_base.dart';

class LogViewerModalPanel extends StatefulWidget {
  const LogViewerModalPanel({super.key});

  @override
  State<LogViewerModalPanel> createState() => _LogViewerModalPanelState();

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (context) => const LogViewerModalPanel(),
    );
  }
}

class _LogViewerModalPanelState extends State<LogViewerModalPanel> {
  String _keyword = '';

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<TerminalAppState>(context);
    final allItems = appState.todayLogs.reversed.toList(growable: false);

    return ModalPanelBase(
      title: l(appState, AppStrings.values.logs),
      width: 800,
      height: 600,
      child: allItems.isEmpty
          ? Center(
              child: Text(
                l(appState, AppStrings.values.noLogs),
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
              ),
            )
          : _buildContent(context, appState, allItems),
    );
  }

  Widget _buildContent(BuildContext context, TerminalAppState appState, List<String> allItems) {
    final items = _applyFilter(allItems);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l(appState, AppStrings.values.todayVar, params: {'count': '${items.length}'}),
                  style: AppTextStyles.bodySmall,
                ),
              ),
              SizedBox(
                width: 260,
                height: 34,
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    hintText: l(appState, AppStrings.values.logSearchHint),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    if (!mounted) return;
                    setState(() => _keyword = value);
                  },
                ),
              ),
              const SizedBox(width: 8),

            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    l(appState, AppStrings.values.noLogs),
                    style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                      children: _buildHighlightedLogSpans(items),
                    ),
                  ),
                ),
        ),
      ],
    );
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
      spans.add(TextSpan(
        text: line.substring(matchIndex, end),
        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
      ));
      cursor = end;
    }
    return spans;
  }

  List<String> _applyFilter(List<String> items) {
    final normalizedKeyword = _keyword.trim().toLowerCase();
    return items.where((line) {
      if (normalizedKeyword.isNotEmpty && !line.toLowerCase().contains(normalizedKeyword)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }
}

