import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfFileViewer extends StatefulWidget {
  const PdfFileViewer({
    required this.filePath,
    this.initialPageNumber = 1,
    this.onPersistPageNumber,
    super.key,
  });

  final String filePath;
  final int initialPageNumber;
  final ValueChanged<int>? onPersistPageNumber;

  @override
  State<PdfFileViewer> createState() => _PdfFileViewerState();
}

class _PdfFileViewerState extends State<PdfFileViewer> {
  final PdfViewerController _controller = PdfViewerController();
  Timer? _thumbFadeTimer;
  Timer? _persistDebounce;
  bool _thumbVisible = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onViewerMatrixChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onViewerMatrixChanged);
    _thumbFadeTimer?.cancel();
    _persistDebounce?.cancel();
    super.dispose();
  }

  void _onViewerMatrixChanged() {
    _showThumbTemporarily();
    _schedulePersistPage();
  }

  void _showThumbTemporarily() {
    if (!mounted) return;
    if (!_thumbVisible) {
      setState(() {
        _thumbVisible = true;
      });
    }
    _thumbFadeTimer?.cancel();
    _thumbFadeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || !_thumbVisible) return;
      setState(() {
        _thumbVisible = false;
      });
    });
  }

  void _schedulePersistPage() {
    if (widget.onPersistPageNumber == null) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || !_controller.isReady) return;
      final pageNumber = _controller.pageNumber;
      if (pageNumber == null) return;
      widget.onPersistPageNumber!(pageNumber);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewer.file(
      widget.filePath,
      controller: _controller,
      initialPageNumber: widget.initialPageNumber <= 0
          ? 1
          : widget.initialPageNumber,
      params: PdfViewerParams(
        margin: 0,
        backgroundColor: Colors.white,
        onInteractionStart: (_) => _showThumbTemporarily(),
        onInteractionUpdate: (_) => _showThumbTemporarily(),
        onPageChanged: (pageNumber) {
          if (pageNumber == null || widget.onPersistPageNumber == null) {
            return;
          }
          widget.onPersistPageNumber!(pageNumber);
        },
        viewerOverlayBuilder: (context, size, handleLinkTap) {
          if (!_thumbVisible) {
            return const <Widget>[];
          }
          return <Widget>[
            PdfViewerScrollThumb(
              controller: _controller,
              orientation: ScrollbarOrientation.right,
              margin: 4,
              thumbSize: const Size(8, 76),
              thumbBuilder: (context, thumbSize, pageNumber, controller) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              },
            ),
          ];
        },
      ),
    );
  }
}

