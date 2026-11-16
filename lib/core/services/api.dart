import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';

import '../../app/app_config.dart';
import '../utils/split_calculator.dart';

/// A failure with a message that is safe to show to the user.
class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Every write that touches money or membership goes through these Cloud
/// Functions. The server re-checks permissions, statuses and amounts, so the
/// app never sets a status or an amount directly.
class Api extends GetxService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion);

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final result = await _functions
          .httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call<dynamic>(data);
      final value = result.data;
      return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw ApiException(_message(e));
    } catch (_) {
      throw const ApiException("Couldn't reach the server. Check your connection and try again.");
    }
  }

  String _message(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unavailable':
      case 'deadline-exceeded':
        return "Couldn't reach the server. Check your connection and try again.";
      case 'internal':
      case 'unknown':
        return 'Something went wrong on our side. Please try again.';
      default:
        return (e.message == null || e.message!.isEmpty) ? 'Something went wrong. Please try again.' : e.message!;
    }
  }

  // ---- profile -------------------------------------------------------------

  Future<void> updateProfile({required String name, String? phone, String? photoUrl}) =>
      _call('updateProfile', {'name': name, 'phone': phone ?? '', 'photoUrl': photoUrl});

  // ---- rooms ---------------------------------------------------------------

  Future<String> createRoom({required String name, required String currency, required String icon}) async =>
      (await _call('createRoom', {'name': name, 'currency': currency, 'icon': icon}))['roomId'] as String;

  Future<Map<String, dynamic>> previewRoom(String codeOrToken) => _call('previewRoom', {'codeOrToken': codeOrToken});

  /// Returns the room id and "joined", "requested" or "already".
  Future<Map<String, dynamic>> joinRoom(String codeOrToken) => _call('joinRoom', {'codeOrToken': codeOrToken});

  Future<void> respondJoinRequest(String roomId, String uid, {required bool approve}) =>
      _call('respondJoinRequest', {'roomId': roomId, 'uid': uid, 'approve': approve});

  Future<void> updateRoom(String roomId, {String? name, String? icon, bool? requireApproval}) => _call('updateRoom', {
        'roomId': roomId,
        'name': ?name,
        'icon': ?icon,
        'requireApproval': ?requireApproval,
      });

  Future<void> resetInvite(String roomId) => _call('resetInvite', {'roomId': roomId});
  Future<void> removeMember(String roomId, String uid) => _call('removeMember', {'roomId': roomId, 'uid': uid});
  Future<void> leaveRoom(String roomId) => _call('leaveRoom', {'roomId': roomId});
  Future<void> transferOwnership(String roomId, String uid) =>
      _call('transferOwnership', {'roomId': roomId, 'uid': uid});
  Future<void> setRole(String roomId, String uid, String role) =>
      _call('setRole', {'roomId': roomId, 'uid': uid, 'role': role});

  // ---- invites -------------------------------------------------------------

  /// Returns true when that email already has an account.
  Future<bool> inviteByEmail(String roomId, String email) async =>
      (await _call('inviteByEmail', {'roomId': roomId, 'email': email}))['registered'] == true;

  /// Returns the room id when the invite was accepted.
  Future<String?> respondInvite(String inviteId, {required bool accept}) async =>
      (await _call('respondInvite', {'inviteId': inviteId, 'accept': accept}))['roomId'] as String?;

  Future<void> cancelInvite(String inviteId) => _call('cancelInvite', {'inviteId': inviteId});

  // ---- splits --------------------------------------------------------------

  Map<String, dynamic> _splitPayload({
    required String roomId,
    required String title,
    required int totalMinor,
    required String paidBy,
    required SplitType type,
    required List<ParticipantInput> participants,
    String? dueDate,
    String? note,
    String? receiptUrl,
  }) =>
      {
        'roomId': roomId,
        'title': title,
        'totalMinor': totalMinor,
        'paidBy': paidBy,
        'splitType': type.id,
        'participants': [
          for (final p in participants) {'uid': p.uid, if (type != SplitType.equal) 'value': p.value},
        ],
        'dueDate': dueDate,
        'note': note,
        'receiptUrl': receiptUrl,
      };

  Future<String> createSplit({
    required String roomId,
    required String title,
    required int totalMinor,
    required String paidBy,
    required SplitType type,
    required List<ParticipantInput> participants,
    String? dueDate,
    String? note,
    String? receiptUrl,
    int? repeatDayOfMonth,
    int repeatDueAfterDays = 0,
    String? repeatEndPeriod,
  }) async {
    final payload = _splitPayload(
      roomId: roomId, title: title, totalMinor: totalMinor, paidBy: paidBy, type: type,
      participants: participants, dueDate: dueDate, note: note, receiptUrl: receiptUrl,
    );
    if (repeatDayOfMonth != null) {
      payload['repeat'] = {
        'dayOfMonth': repeatDayOfMonth,
        'dueAfterDays': repeatDueAfterDays,
        'endPeriod': repeatEndPeriod,
      };
    }
    return (await _call('createSplit', payload))['splitId'] as String;
  }

  Future<void> updateSplit({
    required String roomId,
    required String splitId,
    required String title,
    required int totalMinor,
    required String paidBy,
    required SplitType type,
    required List<ParticipantInput> participants,
    String? dueDate,
    String? note,
    String? receiptUrl,
  }) =>
      _call('updateSplit', {
        ..._splitPayload(
          roomId: roomId, title: title, totalMinor: totalMinor, paidBy: paidBy, type: type,
          participants: participants, dueDate: dueDate, note: note, receiptUrl: receiptUrl,
        ),
        'splitId': splitId,
      });

  Future<void> deleteSplit(String roomId, String splitId) =>
      _call('deleteSplit', {'roomId': roomId, 'splitId': splitId});

  Future<void> setRuleActive(String roomId, String ruleId, bool active) =>
      _call('updateRule', {'roomId': roomId, 'ruleId': ruleId, 'active': active});
  Future<void> endRule(String roomId, String ruleId) =>
      _call('updateRule', {'roomId': roomId, 'ruleId': ruleId, 'end': true});

  // ---- payments ------------------------------------------------------------

  Future<void> markPaid(String roomId, String splitId, {required String method, String? note, String? proofUrl}) =>
      _call('markPaid', {'roomId': roomId, 'splitId': splitId, 'method': method, 'note': note, 'proofUrl': proofUrl});

  Future<void> confirmShare(String roomId, String splitId, String uid) =>
      _call('confirmShare', {'roomId': roomId, 'splitId': splitId, 'uid': uid});

  Future<void> rejectShare(String roomId, String splitId, String uid, String reason) =>
      _call('rejectShare', {'roomId': roomId, 'splitId': splitId, 'uid': uid, 'reason': reason});

  Future<void> markPaidDirect(String roomId, String splitId, String uid) =>
      _call('markPaidDirect', {'roomId': roomId, 'splitId': splitId, 'uid': uid});

  Future<void> undoPaid(String roomId, String splitId, String uid) =>
      _call('undoPaid', {'roomId': roomId, 'splitId': splitId, 'uid': uid});
}
