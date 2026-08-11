import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/screens/sign_in_screen.dart';
import 'package:journal_app/theme/app_theme.dart';

void main() {
  testWidgets('tapping Sign in with Google calls onSignIn', (tester) async {
    var signInCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: SignInScreen(onSignIn: () async => signInCalled = true, onSkip: () {}),
    ));
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();

    expect(signInCalled, isTrue);
  });

  testWidgets('tapping Skip calls onSkip', (tester) async {
    var skipCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: SignInScreen(onSignIn: () async {}, onSkip: () => skipCalled = true),
    ));
    await tester.tap(find.text('Skip for now'));

    expect(skipCalled, isTrue);
  });

  testWidgets('sign-in button uses the amber accent background', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: appTheme,
      home: SignInScreen(onSignIn: () async {}, onSkip: () {}),
    ));

    // ElevatedButton itself has no explicit `style:` set (it relies on the
    // ambient ElevatedButtonTheme), so the widget's own `.style` is null --
    // the resolved color only exists on the Material it renders internally.
    final material = tester.widget<Material>(
      find.descendant(of: find.byType(ElevatedButton), matching: find.byType(Material)).first,
    );

    expect(material.color, AppColors.accent);
  });
}
