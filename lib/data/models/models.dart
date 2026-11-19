// Plain data classes for the documents the app reads from Firestore.
// The app never writes these: every change goes through a Cloud Function.
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date_utils.dart';
import '../../core/utils/split_calculator.dart';

typedef Doc = DocumentSnapshot<Map<String, dynamic>>;

DateTime? _time(dynamic v) => v is Timestamp ? v.toDate() : null;
List<String> _strings(dynamic v) => v is List ? v.whereType<String>().toList() : const [];

class AppUser {
  AppUser({required this.uid, required this.name, this.emailLower, this.phone, this.photoUrl});
  final String uid;
  final String name;
  final String? emailLower;
  final String? phone;
  final String? photoUrl;

  factory AppUser.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return AppUser(
      uid: doc.id,
      name: (d['name'] as String?) ?? '',
      emailLower: d['emailLower'] as String?,
      phone: d['phone'] as String?,
      photoUrl: d['photoUrl'] as String?,
    );
  }
}

class Room {
  Room({
    required this.id,
    required this.name,
    required this.icon,
    required this.currency,
    required this.code,
    required this.inviteToken,
    required this.ownerId,
    required this.adminIds,
    required this.memberIds,
    required this.requireApproval,
  });
  final String id;
  final String name;
  final String icon;
  final String currency;
  final String code;
  final String inviteToken;
  final String ownerId;
  final List<String> adminIds;
  final List<String> memberIds;
  final bool requireApproval;

  /// Owner or admin.
  bool isManager(String uid) => ownerId == uid || adminIds.contains(uid);

  factory Room.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return Room(
      id: doc.id,
      name: (d['name'] as String?) ?? 'Room',
      icon: (d['icon'] as String?) ?? '🏠',
      currency: (d['currency'] as String?) ?? 'QAR',
      code: (d['code'] as String?) ?? '',
      inviteToken: (d['inviteToken'] as String?) ?? '',
      ownerId: (d['ownerId'] as String?) ?? '',
      adminIds: _strings(d['adminIds']),
      memberIds: _strings(d['memberIds']),
      requireApproval: d['requireApproval'] == true,
    );
  }
}

class Member {
  Member({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.status,
    required this.netMinor,
    this.photoUrl,
  });
  final String uid;
  final String displayName;
  final String role; // owner, admin, member
  final String status; // active, left, removed
  /// Cached balance: positive means the room owes them, negative means they owe.
  final int netMinor;
  final String? photoUrl;

  bool get isActive => status == 'active';

  factory Member.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return Member(
      uid: doc.id,
      displayName: (d['displayName'] as String?) ?? 'Someone',
      role: (d['role'] as String?) ?? 'member',
      status: (d['status'] as String?) ?? 'active',
      netMinor: (d['netMinor'] as num?)?.toInt() ?? 0,
      photoUrl: d['photoUrl'] as String?,
    );
  }

  static Member unknown(String uid) =>
      Member(uid: uid, displayName: 'Someone', role: 'member', status: 'left', netMinor: 0);
}

enum ShareStatus {
  unpaid('unpaid', 'Unpaid'),
  markedPaid('marked_paid', 'Marked paid'),
  paid('paid', 'Paid');

  const ShareStatus(this.id, this.label);
  final String id;
  final String label;

  static ShareStatus fromId(String? id) =>
      ShareStatus.values.firstWhere((s) => s.id == id, orElse: () => ShareStatus.unpaid);
}

class ShareSummary {
  const ShareSummary(this.amountMinor, this.status);
  final int amountMinor;
  final ShareStatus status;
}

class Split {
  Split({
    required this.id,
    required this.roomId,
    required this.title,
    required this.totalMinor,
    required this.currency,
    required this.paidBy,
    required this.createdBy,
    required this.splitType,
    required this.participantIds,
    required this.inputs,
    required this.shareSummary,
    required this.settled,
    this.dueDate,
    this.note,
    this.receiptUrl,
    this.ruleId,
    this.periodKey,
    this.createdAt,
    this.commentCount = 0,
  });
  final String id;
  final String roomId;
  final String title;
  final int totalMinor;
  final String currency;
  final String paidBy;
  final String createdBy;
  final SplitType splitType;
  final List<String> participantIds;

  /// What was typed per person (exact amount, basis points or weight).
  final Map<String, int?> inputs;
  final Map<String, ShareSummary> shareSummary;
  final bool settled;
  final String? dueDate;
  final String? note;
  final String? receiptUrl;
  final String? ruleId;
  final String? periodKey;
  final DateTime? createdAt;
  final int commentCount;

  /// "Rent · Dec 2026" for a monthly bill, otherwise just the title.
  String get label => Dates.splitLabel(title, periodKey);
  bool get isRecurring => ruleId != null;
  bool get isOverdue => !settled && Dates.isOverdue(dueDate);
  int get paidCount => shareSummary.values.where((s) => s.status == ShareStatus.paid).length;

  /// True once someone other than the payer has a Paid share.
  bool get hasPayments =>
      shareSummary.entries.any((e) => e.key != paidBy && e.value.status == ShareStatus.paid);

  /// Still owed to the payer.
  int get outstandingMinor => shareSummary.entries
      .where((e) => e.key != paidBy && e.value.status != ShareStatus.paid)
      .fold(0, (s, e) => s + e.value.amountMinor);

  factory Split.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    final summary = <String, ShareSummary>{};
    (d['shareSummary'] as Map<String, dynamic>? ?? const {}).forEach((uid, v) {
      final m = v as Map<String, dynamic>;
      summary[uid] = ShareSummary((m['amountMinor'] as num?)?.toInt() ?? 0, ShareStatus.fromId(m['status'] as String?));
    });
    final inputs = <String, int?>{};
    (d['inputs'] as Map<String, dynamic>? ?? const {}).forEach((uid, v) => inputs[uid] = (v as num?)?.toInt());
    return Split(
      id: doc.id,
      roomId: doc.reference.parent.parent?.id ?? '',
      title: (d['title'] as String?) ?? '',
      totalMinor: (d['totalMinor'] as num?)?.toInt() ?? 0,
      currency: (d['currency'] as String?) ?? 'QAR',
      paidBy: (d['paidBy'] as String?) ?? '',
      createdBy: (d['createdBy'] as String?) ?? '',
      splitType: SplitType.fromId(d['splitType'] as String?),
      participantIds: _strings(d['participantIds']),
      inputs: inputs,
      shareSummary: summary,
      settled: d['status'] == 'settled',
      dueDate: d['dueDate'] as String?,
      note: d['note'] as String?,
      receiptUrl: d['receiptUrl'] as String?,
      ruleId: d['ruleId'] as String?,
      periodKey: d['periodKey'] as String?,
      createdAt: _time(d['createdAt']),
      commentCount: (d['commentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class Comment {
  Comment({required this.id, required this.authorId, required this.authorName, required this.text, this.createdAt});
  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final DateTime? createdAt;

  factory Comment.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return Comment(
      id: doc.id,
      authorId: (d['authorId'] as String?) ?? '',
      authorName: (d['authorName'] as String?) ?? 'Someone',
      text: (d['text'] as String?) ?? '',
      createdAt: _time(d['createdAt']),
    );
  }
}

/// One person's portion of a split.
class Share {
  Share({
    required this.userId,
    required this.roomId,
    required this.splitId,
    required this.payerId,
    required this.amountMinor,
    required this.currency,
    required this.splitTitle,
    required this.status,
    this.periodKey,
    this.dueDate,
    this.method,
    this.note,
    this.proofUrl,
    this.rejectReason,
    this.markedAt,
    this.confirmedAt,
  });
  final String userId;
  final String roomId;
  final String splitId;
  final String payerId;
  final int amountMinor;
  final String currency;
  final String splitTitle;
  final ShareStatus status;
  final String? periodKey;
  final String? dueDate;
  final String? method;
  final String? note;
  final String? proofUrl;
  final String? rejectReason;
  final DateTime? markedAt;
  final DateTime? confirmedAt;

  String get label => Dates.splitLabel(splitTitle, periodKey);
  bool get isPayerShare => userId == payerId;
  bool get isOverdue => status != ShareStatus.paid && Dates.isOverdue(dueDate);

  String get methodLabel => switch (method) {
        'cash' => 'Cash',
        'bank_transfer' => 'Bank transfer',
        'other' => 'Other',
        _ => '',
      };

  factory Share.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return Share(
      userId: (d['userId'] as String?) ?? doc.id,
      roomId: (d['roomId'] as String?) ?? '',
      splitId: (d['splitId'] as String?) ?? '',
      payerId: (d['payerId'] as String?) ?? '',
      amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
      currency: (d['currency'] as String?) ?? 'QAR',
      splitTitle: (d['splitTitle'] as String?) ?? '',
      status: ShareStatus.fromId(d['status'] as String?),
      periodKey: d['periodKey'] as String?,
      dueDate: d['dueDate'] as String?,
      method: d['method'] as String?,
      note: d['note'] as String?,
      proofUrl: d['proofUrl'] as String?,
      rejectReason: d['rejectReason'] as String?,
      markedAt: _time(d['markedAt']),
      confirmedAt: _time(d['confirmedAt']),
    );
  }
}

/// The template each month's split is copied from.
class RecurringRule {
  RecurringRule({
    required this.id,
    required this.title,
    required this.totalMinor,
    required this.currency,
    required this.paidBy,
    required this.createdBy,
    required this.dayOfMonth,
    required this.dueAfterDays,
    required this.active,
    required this.participantCount,
    required this.splitType,
    required this.participants,
    this.skipPeriods = const [],
    this.endPeriod,
    this.lastGeneratedPeriod,
    this.pausedReason,
  });
  final String id;
  final String title;
  final int totalMinor;
  final String currency;
  final String paidBy;
  final String createdBy;
  final int dayOfMonth; // 1-28, or -1 for the last day of the month
  final int dueAfterDays;
  final bool active;
  final int participantCount;
  final SplitType splitType;
  final List<ParticipantInput> participants;
  final List<String> skipPeriods;
  final String? endPeriod;
  final String? lastGeneratedPeriod;
  final String? pausedReason;

  String get scheduleLabel {
    final day = dayOfMonth == -1 ? 'the last day' : 'the ${Dates.ordinal(dayOfMonth)}';
    final due = dueAfterDays == 0
        ? 'due the same day'
        : 'due $dueAfterDays day${dueAfterDays == 1 ? '' : 's'} later';
    return 'Every month on $day · $due';
  }

  /// The next month this rule would create a split for (skipped or not).
  String get nextPeriod {
    final current = Dates.period(DateTime.now());
    final last = lastGeneratedPeriod ?? '';
    return last.compareTo(current) >= 0 ? Dates.nextPeriod(last) : current;
  }

  bool get nextIsSkipped => skipPeriods.contains(nextPeriod);

  /// When the next split will actually be created, or null if the rule has ended.
  DateTime? get nextRun {
    var p = nextPeriod;
    for (var i = 0; i < 24 && skipPeriods.contains(p); i++) {
      p = Dates.nextPeriod(p);
    }
    if (endPeriod != null && p.compareTo(endPeriod!) > 0) return null;
    return Dates.runDate(p, dayOfMonth);
  }

  factory RecurringRule.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return RecurringRule(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      totalMinor: (d['totalMinor'] as num?)?.toInt() ?? 0,
      currency: (d['currency'] as String?) ?? 'QAR',
      paidBy: (d['paidBy'] as String?) ?? '',
      createdBy: (d['createdBy'] as String?) ?? '',
      dayOfMonth: (d['dayOfMonth'] as num?)?.toInt() ?? 1,
      dueAfterDays: (d['dueAfterDays'] as num?)?.toInt() ?? 0,
      active: d['active'] == true,
      participantCount: (d['participants'] as List?)?.length ?? 0,
      splitType: SplitType.fromId(d['splitType'] as String?),
      participants: [
        for (final p in (d['participants'] as List? ?? const []))
          if (p is Map) ParticipantInput(p['uid'] as String, (p['value'] as num?)?.toInt()),
      ],
      skipPeriods: _strings(d['skipPeriods']),
      endPeriod: d['endPeriod'] as String?,
      lastGeneratedPeriod: d['lastGeneratedPeriod'] as String?,
      pausedReason: d['pausedReason'] as String?,
    );
  }
}

class Activity {
  Activity({
    required this.id,
    required this.type,
    required this.actorId,
    required this.actorName,
    this.splitId,
    this.splitTitle,
    this.targetUserId,
    this.targetName,
    this.amountMinor,
    this.detail,
    this.createdAt,
  });
  final String id;
  final String type;
  final String actorId;
  final String actorName;
  final String? splitId;
  final String? splitTitle;
  final String? targetUserId;
  final String? targetName;
  final int? amountMinor;
  final String? detail;
  final DateTime? createdAt;

  factory Activity.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return Activity(
      id: doc.id,
      type: (d['type'] as String?) ?? '',
      actorId: (d['actorId'] as String?) ?? '',
      actorName: (d['actorName'] as String?) ?? 'Someone',
      splitId: d['splitId'] as String?,
      splitTitle: d['splitTitle'] as String?,
      targetUserId: d['targetUserId'] as String?,
      targetName: d['targetName'] as String?,
      amountMinor: (d['amountMinor'] as num?)?.toInt(),
      detail: d['detail'] as String?,
      createdAt: _time(d['createdAt']),
    );
  }
}

class Invite {
  Invite({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.roomIcon,
    required this.emailLower,
    required this.invitedByName,
  });
  final String id;
  final String roomId;
  final String roomName;
  final String roomIcon;
  final String emailLower;
  final String invitedByName;

  factory Invite.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return Invite(
      id: doc.id,
      roomId: (d['roomId'] as String?) ?? '',
      roomName: (d['roomName'] as String?) ?? 'a room',
      roomIcon: (d['roomIcon'] as String?) ?? '🏠',
      emailLower: (d['emailLower'] as String?) ?? '',
      invitedByName: (d['invitedByName'] as String?) ?? 'Someone',
    );
  }
}

class JoinRequest {
  JoinRequest({required this.uid, required this.displayName, required this.via, this.photoUrl});
  final String uid;
  final String displayName;
  final String via; // code or link
  final String? photoUrl;

  factory JoinRequest.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return JoinRequest(
      uid: doc.id,
      displayName: (d['displayName'] as String?) ?? 'Someone',
      via: (d['via'] as String?) ?? 'code',
      photoUrl: d['photoUrl'] as String?,
    );
  }
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    this.roomId,
    this.splitId,
    this.inviteId,
    this.createdAt,
  });
  final String id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final String? roomId;
  final String? splitId;
  final String? inviteId;
  final DateTime? createdAt;

  factory AppNotification.fromDoc(Doc doc) {
    final d = doc.data() ?? const {};
    return AppNotification(
      id: doc.id,
      type: (d['type'] as String?) ?? '',
      title: (d['title'] as String?) ?? '',
      body: (d['body'] as String?) ?? '',
      read: d['read'] == true,
      roomId: d['roomId'] as String?,
      splitId: d['splitId'] as String?,
      inviteId: d['inviteId'] as String?,
      createdAt: _time(d['createdAt']),
    );
  }
}
