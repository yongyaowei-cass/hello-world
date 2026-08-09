import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/screens/sign_in_screen.dart';

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
}
