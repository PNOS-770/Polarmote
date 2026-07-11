import 'package:flutter/material.dart';

import '../manager/banner_manager.dart';
import '../model/banner_data.dart';
import '../overlay/banner_positioner.dart';
import '../theme/banner_theme.dart';
import '../widget/banner_widget.dart';

typedef BannerWidgetBuilder = Widget Function(
  BuildContext context,
  BannerData data,
  VoidCallback onDismiss,
  double width,
);

class BannerOverlayHost extends StatelessWidget {
  const BannerOverlayHost({
    super.key,
    required this.child,
    this.bannerBuilder,
  });

  final Widget child;
  final BannerWidgetBuilder? bannerBuilder;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          ignoring: false,
          child: SafeArea(
            child: AnimatedBuilder(
              animation: BannerManager.instance.banners,
              builder: (context, _) {
                final banners = BannerManager.instance.banners.value;
                if (banners.isEmpty) {
                  return const SizedBox.shrink();
                }
                final width = BannerPositioner.widthFor(context);
                return Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: BannerPositioner.stackPadding(context),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final banner in banners) ...[
                          if (bannerBuilder != null)
                            bannerBuilder!(context, banner, () => BannerManager.dismiss(banner.id), width)
                          else
                            BannerWidget(
                              key: ValueKey(banner.id),
                              data: banner,
                              width: width,
                              onDismiss: () => BannerManager.dismiss(banner.id),
                            ),
                          const SizedBox(height: BannerPositioner.spacing),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

Widget withBannerOverlay(
  BuildContext context,
  Widget child, {
  BannerWidgetBuilder? bannerBuilder,
}) {
  return BannerTheme(
    data: BannerThemeData.fallback(context),
    child: BannerOverlayHost(
      child: child,
      bannerBuilder: bannerBuilder,
    ),
  );
}
