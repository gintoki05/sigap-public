import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF1d3557);
  static const red = Color(0xFFe63946);
  static const background = Color(0xFFf8f9fa);
  static const white = Color(0xFFFFFFFF);
  static const textDark = Color(0xFF212529);
  static const textGrey = Color(0xFF6c757d);

  static const urgencyGreen = Color(0xFF2d6a4f);
  static const urgencyYellow = Color(0xFFe9c46a);
  static const urgencyRed = Color(0xFFe63946);
}

enum UrgencyLevel { green, yellow, red }

extension UrgencyLevelExtension on UrgencyLevel {
  String get label {
    switch (this) {
      case UrgencyLevel.green:
        return 'Tangani Sendiri';
      case UrgencyLevel.yellow:
        return 'Segera ke Klinik';
      case UrgencyLevel.red:
        return 'Panggil Bantuan';
    }
  }

  Color get color {
    switch (this) {
      case UrgencyLevel.green:
        return AppColors.urgencyGreen;
      case UrgencyLevel.yellow:
        return AppColors.urgencyYellow;
      case UrgencyLevel.red:
        return AppColors.urgencyRed;
    }
  }
}
