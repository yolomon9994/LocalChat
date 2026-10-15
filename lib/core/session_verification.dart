import 'dart:convert';

enum VerificationScope { direct, group }

/// Public handshake identifiers for an in-person comparison, never a login token.
class VerificationQr {
  const VerificationQr({
    required this.scope,
    required this.session,
    required this.sender,
    required this.receiver,
  });
  final VerificationScope scope;
  final String session, sender, receiver;
  static final _digest = RegExp(r'^[a-f0-9]{64}$');
  String get encode => jsonEncode({
    'type': 'LocalChat/session-verification',
    'v': 1,
    'mode': scope.name,
    'session': session,
    'from': sender,
    'to': receiver,
  });
  static VerificationQr parse(String text) {
    const invalid = FormatException('This is not a LocalChat verification QR.');
    if (text.length > 512 || utf8.encode(text).length > 512) throw invalid;
    Object? raw;
    try {
      raw = jsonDecode(text);
    } catch (_) {
      throw invalid;
    }
    if (raw is! Map ||
        raw.length != 6 ||
        raw['type'] != 'LocalChat/session-verification' ||
        raw['v'] != 1 ||
        !['direct', 'group'].contains(raw['mode']) ||
        ['session', 'from', 'to'].any(
          (k) =>
              raw is! Map ||
              raw[k] is! String ||
              !_digest.hasMatch(raw[k] as String),
        ) ||
        raw['from'] == raw['to']) {
      throw invalid;
    }
    return VerificationQr(
      scope: raw['mode'] == 'direct'
          ? VerificationScope.direct
          : VerificationScope.group,
      session: raw['session'] as String,
      sender: raw['from'] as String,
      receiver: raw['to'] as String,
    );
  }

  bool matchesRemote(String text) {
    try {
      final other = parse(text);
      return other.scope == scope &&
          other.session == session &&
          other.sender == receiver &&
          other.receiver == sender;
    } on FormatException {
      return false;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VerificationQr &&
      scope == other.scope &&
      session == other.session &&
      sender == other.sender &&
      receiver == other.receiver;
  @override
  int get hashCode => Object.hash(scope, session, sender, receiver);
}

/// Captured before navigation/queued work; owners must recheck every field.
class VerificationRequest {
  const VerificationRequest({
    required this.owner,
    required this.sessionToken,
    required this.interactionRevision,
    required this.qr,
    required this.peerName,
    this.linkId,
  });
  final Object owner, sessionToken;
  final int interactionRevision;
  final VerificationQr qr;
  final String peerName;
  final String? linkId;
}
