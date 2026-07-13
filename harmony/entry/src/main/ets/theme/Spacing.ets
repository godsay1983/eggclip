export class EggClipSpacing {
  static readonly pagePadding: number = 20;
  static readonly cardPadding: number = 16;
  static readonly sectionGap: number = 14;
  static readonly itemGap: number = 10;
  static readonly radiusLarge: number = 24;
  static readonly radiusMedium: number = 16;
  // Floating navigation overlaps the page by design. Keep its geometry and
  // the scrollable content inset in one contract so the final item always
  // clears the bar and its gradient mask. HdsTabs remains responsible for the
  // device-specific system bottom safe area.
  static readonly floatingNavigationItemHeight: number = 54;
  static readonly floatingNavigationBottomMargin: number = 14;
  static readonly floatingNavigationMaskHeight: number = 96;
  static readonly floatingNavigationContentInset: number = 112;
}
