// Read-only live queries. Every write goes through Api (Cloud Functions),
// except marking the user's own notifications read.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/models.dart';

FirebaseFirestore get _db => FirebaseFirestore.instance;

class RoomRepo {
  Stream<List<Room>> myRooms(String uid) => _db
      .collection('rooms')
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.map(Room.fromDoc).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  Stream<Room?> room(String roomId) =>
      _db.collection('rooms').doc(roomId).snapshots().map((d) => d.exists ? Room.fromDoc(d) : null);

  /// Everyone who has ever been in the room, so old splits can still show names.
  Stream<List<Member>> members(String roomId) => _db
      .collection('rooms/$roomId/members')
      .snapshots()
      .map((s) => s.docs.map(Member.fromDoc).toList());

  Stream<List<JoinRequest>> joinRequests(String roomId) => _db
      .collection('rooms/$roomId/joinRequests')
      .snapshots()
      .map((s) => s.docs.map(JoinRequest.fromDoc).toList());

  Stream<List<RecurringRule>> rules(String roomId) => _db
      .collection('rooms/$roomId/recurringRules')
      .snapshots()
      .map((s) => s.docs.map(RecurringRule.fromDoc).toList()..sort((a, b) => a.title.compareTo(b.title)));

  /// The room log, newest first. With [splitId], only that split's history.
  Stream<List<Activity>> activity(String roomId, {String? splitId, int limit = 100}) {
    Query<Map<String, dynamic>> q = _db.collection('rooms/$roomId/activity');
    if (splitId != null) q = q.where('splitId', isEqualTo: splitId);
    return q
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(Activity.fromDoc).toList());
  }
}

class SplitRepo {
  Stream<List<Split>> splits(String roomId) => _db
      .collection('rooms/$roomId/splits')
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots()
      .map((s) => s.docs.map(Split.fromDoc).toList());

  Stream<List<Comment>> comments(String roomId, String splitId) => _db
      .collection('rooms/$roomId/splits/$splitId/comments')
      .orderBy('createdAt')
      .limitToLast(200)
      .snapshots()
      .map((s) => s.docs.map(Comment.fromDoc).toList());

  Stream<Split?> split(String roomId, String splitId) => _db
      .doc('rooms/$roomId/splits/$splitId')
      .snapshots()
      .map((d) => d.exists ? Split.fromDoc(d) : null);
}

class ShareRepo {
  Stream<List<Share>> shares(String roomId, String splitId) => _db
      .collection('rooms/$roomId/splits/$splitId/shares')
      .snapshots()
      .map((s) => s.docs.map(Share.fromDoc).toList());

  static const _open = ['unpaid', 'marked_paid'];

  /// Everything I still owe, across all rooms, soonest due first.
  Stream<List<Share>> iOwe(String uid) => _db
      .collectionGroup('shares')
      .where('userId', isEqualTo: uid)
      .where('status', whereIn: _open)
      .orderBy('dueDate')
      .snapshots()
      .map((s) => s.docs.map(Share.fromDoc).toList());

  /// Everything still owed to me, across all rooms.
  Stream<List<Share>> owedToMe(String uid) => _db
      .collectionGroup('shares')
      .where('payerId', isEqualTo: uid)
      .where('status', whereIn: _open)
      .snapshots()
      .map((s) => s.docs.map(Share.fromDoc).toList());
}

class InviteRepo {
  /// Email invites waiting for me. Readable only once my email is verified.
  Stream<List<Invite>> pendingFor(String emailLower) => _db
      .collection('invites')
      .where('emailLower', isEqualTo: emailLower)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.map(Invite.fromDoc).toList());

  Stream<List<Invite>> pendingForRoom(String roomId) => _db
      .collection('invites')
      .where('roomId', isEqualTo: roomId)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.map(Invite.fromDoc).toList());
}

class NotificationRepo {
  CollectionReference<Map<String, dynamic>> _col(String uid) => _db.collection('users/$uid/notifications');

  Stream<List<AppNotification>> inbox(String uid) => _col(uid)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(AppNotification.fromDoc).toList());

  Future<void> markRead(String uid, String id) => _col(uid).doc(id).update({'read': true});

  Future<void> markAllRead(String uid, List<AppNotification> items) async {
    final batch = _db.batch();
    for (final n in items.where((n) => !n.read)) {
      batch.update(_col(uid).doc(n.id), {'read': true});
    }
    await batch.commit();
  }

  Future<void> delete(String uid, String id) => _col(uid).doc(id).delete();
}
