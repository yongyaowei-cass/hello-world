import 'package:flutter/material.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, required this.onSignIn, required this.onSkip});

  final Future<void> Function() onSignIn;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sync your journal across devices with Google Drive.'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onSignIn, child: const Text('Sign in with Google')),
            TextButton(onPressed: onSkip, child: const Text('Skip for now')),
          ],
        ),
      ),
    );
  }
}
