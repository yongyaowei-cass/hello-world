import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

class AuthService {
  AuthService()
      : _googleSignIn = GoogleSignIn(
          scopes: ['https://www.googleapis.com/auth/drive.appdata'],
        );

  final GoogleSignIn _googleSignIn;

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<GoogleSignInAccount?> signIn() => _googleSignIn.signIn();

  Future<void> signOut() => _googleSignIn.signOut();

  Future<gapis.AuthClient?> authenticatedClient() =>
      _googleSignIn.authenticatedClient();
}
