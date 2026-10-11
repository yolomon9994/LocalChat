import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/draft_controller.dart';

class ControlledDraftStore extends DemoStore {
  bool failRead = false;
  bool failWrite = false;
  bool failClear = false;
  Completer<void>? blockedWrite;
  @override
  Future<String> draft(String peer) async {
    if (failRead) throw StateError('Private platform detail');
    return super.draft(peer);
  }

  @override
  Future<void> saveDraft(String peer, String text) async {
    await blockedWrite?.future;
    if (failWrite) throw StateError('Private platform detail');
    await super.saveDraft(peer, text);
  }

  @override
  Future<void> clearHistory() async {
    if (failClear) throw StateError('Clear failed');
    await super.clearHistory();
  }
}

void main() {
  test(
    'Deleting one peer invalidates its pending drafts and preserves other peer edits',
    () async {
      final store = ControlledDraftStore();
      final drafts = DraftController(store);
      addTearDown(drafts.dispose);
      await drafts.load('alice');
      await drafts.load('bob');
      store.blockedWrite = Completer<void>();
      drafts.setText('alice', 'Pending Alice');
      await Future<void>.delayed(Duration.zero);
      final deletion = drafts.deleteConversation('alice');
      drafts.setText('alice', 'Must not return');
      drafts.setText('bob', 'Keep Bob');
      store.blockedWrite!.complete();
      await deletion;
      await drafts.settled;
      await drafts.load('alice');
      expect(drafts.textFor('alice'), '');
      expect(await store.draft('alice'), '');
      expect(drafts.textFor('bob'), 'Keep Bob');
      expect(await store.draft('bob'), 'Keep Bob');
    },
  );
  test(
    'Drafts isolate peers, preserve edits across controllers and clear only captured revisions',
    () async {
      final store = DemoStore();
      final drafts = DraftController(store);
      await drafts.load('alice');
      await drafts.load('bob');
      drafts.setText('alice', '  سلام 👋\nAlice  ');
      final oldRevision = drafts.revisionFor('alice');
      drafts.setText('bob', 'Bob');
      drafts.setText('alice', 'A newer edit');
      await drafts.clearAfterSend('alice', oldRevision);
      await drafts.settled;
      expect(drafts.textFor('alice'), 'A newer edit');
      await drafts.clearAfterSend('bob', drafts.revisionFor('bob'));
      expect(await store.draft('bob'), '');
      drafts.dispose();
      final restored = DraftController(store);
      addTearDown(restored.dispose);
      await restored.load('alice');
      expect(restored.textFor('alice'), 'A newer edit');
    },
  );

  test(
    'Load/save failures preserve drafts and retry without exposing storage details',
    () async {
      final store = ControlledDraftStore();
      await store.saveDraft('alice', 'Saved');
      final drafts = DraftController(store);
      addTearDown(drafts.dispose);
      store.failRead = true;
      await drafts.load('alice');
      expect(drafts.isLoaded('alice'), isFalse);
      expect(drafts.errorFor('alice'), isNot(contains('Private')));
      store.failRead = false;
      await drafts.retry('alice');
      expect(drafts.textFor('alice'), 'Saved');
      store.failWrite = true;
      drafts.setText('alice', 'Unwritten');
      await drafts.settled;
      expect(drafts.textFor('alice'), 'Unwritten');
      expect(await store.draft('alice'), 'Saved');
      expect(drafts.errorFor('alice'), contains('not saved'));
      store.failWrite = false;
      await drafts.retry('alice');
      expect(drafts.errorFor('alice'), isNull);
      expect(await store.draft('alice'), 'Unwritten');
      // Failed removal after a send is retryable too.
      store.failWrite = true;
      await drafts.clearAfterSend('alice', drafts.revisionFor('alice'));
      expect(drafts.textFor('alice'), '');
      expect(drafts.errorFor('alice'), isNotNull);
      store.failWrite = false;
      await drafts.retry('alice');
      expect(await store.draft('alice'), '');
    },
  );

  test(
    'History deletion orders pending writes and invalidates edits queued during deletion',
    () async {
      final store = ControlledDraftStore();
      final drafts = DraftController(store);
      addTearDown(drafts.dispose);
      await drafts.load('alice');
      store.blockedWrite = Completer<void>();
      drafts.setText('alice', 'Pending');
      // Start the write, then queue deletion and another edit behind it.
      await Future<void>.delayed(Duration.zero);
      final deletion = drafts.clearHistory();
      drafts.setText('alice', 'Must not resurrect');
      store.blockedWrite!.complete();
      await deletion;
      await drafts.settled;
      await drafts.load('alice');
      expect(drafts.textFor('alice'), '');
      expect(await store.draft('alice'), '');
      drafts.setText('alice', 'A fresh start');
      await drafts.settled;
      expect(await store.draft('alice'), 'A fresh start');
      store.failClear = true;
      await expectLater(drafts.clearHistory(), throwsStateError);
      expect(drafts.textFor('alice'), 'A fresh start');
    },
  );

  test('Closing the owner still completes queued draft persistence', () async {
    final store = ControlledDraftStore();
    final drafts = DraftController(store);
    await drafts.load('alice');
    store.blockedWrite = Completer<void>();
    drafts.setText('alice', 'Last edit');
    await Future<void>.delayed(Duration.zero);
    drafts.dispose();
    store.blockedWrite!.complete();
    await drafts.settled;
    expect(await store.draft('alice'), 'Last edit');
  });
}
