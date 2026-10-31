/// 高德开放平台用户隐私声明状态。
///
/// 对应高德官方《SDK 合规使用方案》：
/// <https://lbs.amap.com/news/sdkhgsy>
///
/// 宿主 App 必须：
/// 1. 在用户同意隐私政策**之前**，先调用 [AMapInitializer.updatePrivacyShow]
///    声明「已展示弹窗 / 弹窗中包含高德隐私条款」的真实状态；
/// 2. 用户同意后再调用 [AMapInitializer.updatePrivacyAgree]。
///
/// 插件不代做授权 UI，只负责把状态同步给原生 SDK。
class AMapPrivacyStatement {
  /// 隐私弹窗是否包含高德 SDK 隐私协议内容。
  final bool hasContains;

  /// 是否已向用户展示隐私弹窗。
  final bool hasShow;

  /// 用户是否同意高德 SDK 隐私协议。
  final bool hasAgree;

  const AMapPrivacyStatement({
    this.hasContains = false,
    this.hasShow = false,
    this.hasAgree = false,
  });

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
    'hasContains': hasContains,
    'hasShow': hasShow,
    'hasAgree': hasAgree,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AMapPrivacyStatement &&
          other.hasContains == hasContains &&
          other.hasShow == hasShow &&
          other.hasAgree == hasAgree;

  @override
  int get hashCode => Object.hash(hasContains, hasShow, hasAgree);

  @override
  String toString() =>
      'AMapPrivacyStatement(hasContains: $hasContains, hasShow: $hasShow, '
      'hasAgree: $hasAgree)';
}
