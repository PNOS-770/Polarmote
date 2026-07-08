/// 应用间距系统
/// 统一管理所有间距规范，保持布局一致性
class AppSpacing {
  AppSpacing._();

  // ============ 基础间距 ============
  
  /// 极小间距 - 2px
  static const double xs2 = 2.0;
  
  /// 极小间距 - 4px
  static const double xs = 4.0;
  
  /// 小间距 - 8px
  static const double sm = 8.0;
  
  /// 常规间距 - 12px
  static const double md = 12.0;
  
  /// 中间距 - 16px
  static const double lg = 16.0;
  
  /// 大间距 - 20px
  static const double xl = 20.0;
  
  /// 超大间距 - 24px
  static const double xxl = 24.0;
  
  /// 极大间距 - 32px
  static const double xxxl = 32.0;

  // ============ 语义化间距 ============
  
  /// 卡片内边距
  static const double cardPadding = md;
  
  /// 卡片间距
  static const double cardGap = md;
  
  /// 页面边距
  static const double pagePadding = lg;
  
  /// 按钮内边距（水平）
  static const double buttonPaddingH = lg;
  
  /// 按钮内边距（垂直）
  static const double buttonPaddingV = md;
  
  /// 输入框内边距
  static const double inputPadding = md;
  
  /// 列表项内边距
  static const double listItemPadding = md;
  
  /// 分隔线间距
  static const double dividerSpacing = lg;
  
  /// 工具栏高度
  static const double toolbarHeight = 48.0;
  
  /// 底部导航栏高度
  static const double bottomNavHeight = 56.0;
}

