import 'dart:ui' show DisplayFeatureType;
import 'package:flutter/widgets.dart';

class KsBreakpoints {
  static const double compact = 600.0;

  static const double medium = 840.0;

  static const double expanded = 840.0;

  static bool isTablet(BuildContext context) {
    if (isDualScreenSpanned(context)) return true;
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide >= compact && size.height >= 400.0;
  }

  static bool hasHinge(BuildContext context) {
    final features = MediaQuery.of(context).displayFeatures;
    return features.any(
      (f) =>
          f.type == DisplayFeatureType.hinge ||
          f.type == DisplayFeatureType.fold,
    );
  }

  static Rect? getHingeBounds(BuildContext context) {
    final features = MediaQuery.of(context).displayFeatures;
    for (final f in features) {
      if (f.type == DisplayFeatureType.hinge ||
          f.type == DisplayFeatureType.fold) {
        return f.bounds;
      }
    }
    return null;
  }

  static bool isDualScreenSpanned(BuildContext context) {
    final hinge = getHingeBounds(context);
    if (hinge == null) return false;
    final size = MediaQuery.sizeOf(context);
    return hinge.height >= size.height * 0.7 && hinge.width > 0;
  }

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expanded;

  static const double contentMaxWidth = 960.0;

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= expanded) return 24.0;
    if (width >= compact) return 20.0;
    return 16.0;
  }
}
