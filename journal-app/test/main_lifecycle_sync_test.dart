import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:journal_app/main.dart';

// The design spec calls for syncing on app foreground, not just on
// connectivity-restored. handleAppLifecycleStateForSync() is extracted as a
// top-level function (same rationale as runSyncWithStatus in
// main_sync_status_test.dart) so the "only the resumed transition triggers a
// sync" rule is directly testable without a real WidgetsBinding lifecycle
// event or a signed-in AuthService/Drive client.
void main() {
  test('handleAppLifecycleStateForSync triggers a sync when the app resumes', () {
    var syncCalled = false;
    handleAppLifecycleStateForSync(AppLifecycleState.resumed, () => syncCalled = true);

    expect(syncCalled, isTrue);
  });

  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
    AppLifecycleState.hidden,
  ]) {
    test('handleAppLifecycleStateForSync does not trigger a sync on $state', () {
      var syncCalled = false;
      handleAppLifecycleStateForSync(state, () => syncCalled = true);

      expect(syncCalled, isFalse);
    });
  }
}
