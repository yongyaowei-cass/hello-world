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

  /// Attempts to restore a previously-signed-in session without user
  /// interaction (e.g. on cold app start). Returns null if there is no
  /// cached session or it can't be silently restored (never signed in
  /// before, or the session expired) — callers should fall back to an
  /// explicit sign-in flow in that case.
  Future<GoogleSignInAccount?> signInSilently() => _googleSignIn.signInSilently();

  Future<void> signOut() => _googleSignIn.signOut();

  Future<gapis.AuthClient?> authenticatedClient() =>
      _googleSignIn.authenticatedClient();
}
