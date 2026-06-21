/// Shadow tokens for design system

import 'package:flutter/material.dart';
import '../tokens/colors.dart';

class AppShadow {
  static const List<BoxShadow> sm = [
    BoxShadow(
      color: AppColors.neutral900Alpha12,
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> md = [
    BoxShadow(
      color: AppColors.neutral900Alpha12,
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(
      color: AppColors.neutral900Alpha12,
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> xl = [
    BoxShadow(
      color: AppColors.neutral900Alpha12,
      blurRadius: 16,
      offset: Offset(0, 8),
    ),
  ];
}