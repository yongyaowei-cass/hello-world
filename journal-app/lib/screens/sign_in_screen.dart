import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key, required this.onSignIn, required this.onSkip});

  final Future<void> Function() onSignIn;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sync your journal across devices with Google Drive.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onSignIn, child: const Text('Sign in with Google')),
              const SizedBox(height: 8),
              TextButton(onPressed: onSkip, child: const Text('Skip for now')),
            ],
          ),
        ),
      ),
    );
  }
}
