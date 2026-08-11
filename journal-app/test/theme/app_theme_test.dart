import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/theme/app_theme.dart';

void main() {
  test('appTheme is a dark theme using the warm charcoal page background', () {
    expect(appTheme.brightness, Brightness.dark);
    expect(appTheme.scaffoldBackgroundColor, AppColors.pageBackground);
  });

  test('appTheme uses the amber accent for primary/FAB styling', () {
    expect(appTheme.colorScheme.primary, AppColors.accent);
    expect(appTheme.floatingActionButtonTheme.backgroundColor, AppColors.accent);
  });

  test('journalTextStyle uses the Lora font family and primary text color', () {
    expect(journalTextStyle.fontFamily, 'Lora');
    expect(journalTextStyle.color, AppColors.textPrimary);
  });
}
