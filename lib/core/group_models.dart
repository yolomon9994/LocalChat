import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'secure_session.dart';
import 'chat_image.dart';

const groupLimit = 8; // Host plus seven guests; hardware may support fewer.
const groupImageHistoryMaxBytes = 16 * 1024 * 1024;
bool groupIdValid(Object? value) =>
    value is String && RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(value);
Future<String> identityId(String public) async =>
    hex((await Sha256().hash(base64Decode(public))).bytes);

class GroupMember {
  const GroupMember(
    this.id,
    this.name,
    this.public, {
    this.supportsImages = false,
  });
  final String id, name, public;
  final bool supportsImages;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'public': public,
    'images': supportsImages,
  };
  static Future<GroupMember> parse(Map raw) async {
    final public = raw['public'], name = raw['name'];
    if (public is! String ||
        public.length > 64 ||
        base64Decode(public).length != 32 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 32 ||
        raw['id'] != await identityId(public) ||
        (raw.containsKey('images') && raw['images'] is! bool)) {
      throw const FormatException('Invalid group member');
    }
    return GroupMember(
      raw['id'] as String,
      name,
      public,
      supportsImages: raw['images'] == true,
    );
  }
}

/// Signed by the author. Transport encryption is separately host-to-member.
class GroupText {
  GroupText(
    this.envelope, {
    this.receipts = const {},
    this.read = false,
    this.imageBytes,
  });
  final Map<String, dynamic> envelope;
  final Map<String, String> receipts;
  final bool read;
  final Uint8List? imageBytes;
  ChatImage? get image =>
      envelope.containsKey('image') ? ChatImage.parse(envelope['image']) : null;
  String get id => envelope['id'] as String;
  String get author => envelope['authorId'] as String;
  String get name => envelope['name'] as String;
  String get text => envelope['text'] as String;
  int get timestamp => envelope['timestamp'] as int;
  List<String> get targets => List<String>.from(envelope['targets'] as List);
  String get key => '$author/$id';
  GroupText copy({
    Map<String, String>? receipts,
    bool? read,
    Uint8List? imageBytes,
  }) => GroupText(
    envelope,
    receipts: receipts ?? this.receipts,
    read: read ?? this.read,
    imageBytes: imageBytes ?? this.imageBytes,
  );
  Map<String, Object?> toJson() => {
    'envelope': envelope,
    'receipts': receipts,
    'read': read,
    if (image != null && imageBytes != null)
      'imageData': base64Encode(imageBytes!),
  };
  static List<int> _bytes(Map e) => utf8.encode(
    jsonEncode([
      e.containsKey('image')
          ? 'LocalChat/group-image/1'
          : 'LocalChat/group-text/1',
      e['group'],
      e['host'],
      e['epoch'],
      e['view'],
      e['id'],
      e['author'],
      e['name'],
      e['timestamp'],
      e['text'],
      if (e.containsKey('image')) ChatImage.parse(e['image']).toJson(),
      e['targets'],
    ]),
  );
  static Future<GroupText> create(
    SimpleKeyPair identity,
    String name, {
    required String group,
    required String host,
    required String epoch,
    required int view,
    required String text,
    required List<String> targets,
    Uint8List? imageBytes,
  }) async {
    final public = base64Encode((await identity.extractPublicKey()).bytes);
    final e = <String, dynamic>{
      'group': group,
      'host': host,
      'epoch': epoch,
      'view': view,
      'id': randomId(),
      'author': public,
      'authorId': await identityId(public),
      'name': name,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'text': text,
      'targets': [...targets]..sort(),
      if (imageBytes != null)
        'image': (await ChatImage.fromBytes(imageBytes)).toJson(),
    };
    e['signature'] = base64Encode(
      (await Ed25519().sign(_bytes(e), keyPair: identity)).bytes,
    );
    return GroupText(
      e,
      read: true,
      receipts: {for (final id in targets) id: 'pending'},
      imageBytes: imageBytes == null ? null : Uint8List.fromList(imageBytes),
    );
  }

  static Future<GroupText> parse(
    Map raw, {
    bool verifySignature = true,
    bool requireImageData = true,
  }) async {
    if (raw['envelope'] is! Map ||
        raw['receipts'] is! Map ||
        raw['read'] is! bool) {
      throw const FormatException('Invalid group record');
    }
    final e = Map<String, dynamic>.from(raw['envelope'] as Map);
    final image = e.containsKey('image') ? ChatImage.parse(e['image']) : null;
    if ((image != null && e['text'] != 'Image') ||
        (image == null && raw.containsKey('imageData'))) {
      throw const FormatException('Invalid group image record');
    }
    Uint8List? imageBytes;
    if (image != null && (requireImageData || raw.containsKey('imageData'))) {
      final encoded = raw['imageData'];
      if (encoded is! String ||
          encoded.length > ((imageMaxBytes + 2) ~/ 3) * 4) {
        throw const FormatException('Invalid group image contents');
      }
      imageBytes = base64Decode(encoded);
      await image.verify(imageBytes);
    }
    final member = await GroupMember.parse({
      'id': e['authorId'],
      'name': e['name'],
      'public': e['author'],
    });
    if (!groupIdValid(e['group']) ||
        !groupIdValid(e['epoch']) ||
        !groupIdValid(e['id']) ||
        e['host'] is! String ||
        base64Decode(e['host'] as String).length != 32 ||
        e['view'] is! int ||
        (e['view'] as int) < 1 ||
        (e['view'] as int) > 1000000000 ||
        e['text'] is! String ||
        (e['text'] as String).trim().isEmpty ||
        utf8.encode(e['text'] as String).length > 4096 ||
        e['timestamp'] is! int ||
        (e['timestamp'] as int) < 0 ||
        (e['timestamp'] as int) > 8640000000000000 ||
        e['targets'] is! List ||
        (e['targets'] as List).isEmpty ||
        (e['targets'] as List).length > groupLimit) {
      throw const FormatException('Invalid group text');
    }
    final targets = List<String>.from(e['targets'] as List);
    if (targets.toSet().length != targets.length ||
        targets.any((id) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) ||
        jsonEncode(targets) != jsonEncode([...targets]..sort()) ||
        !targets.contains(member.id) ||
        !targets.contains(await identityId(e['host'] as String))) {
      throw const FormatException('Invalid group recipients');
    }
    final sig = base64Decode(e['signature'] as String);
    if (sig.length != 64 ||
        (verifySignature &&
            !await Ed25519().verify(
              _bytes(e),
              signature: Signature(
                sig,
                publicKey: SimplePublicKey(
                  base64Decode(member.public),
                  type: KeyPairType.ed25519,
                ),
              ),
            ))) {
      throw const FormatException('Invalid group author signature');
    }
    final receipts = Map<String, String>.from(raw['receipts'] as Map);
    if (receipts.keys.any((id) => !targets.contains(id)) ||
        receipts.values.any(
          (s) => !{'pending', 'received', 'unconfirmed'}.contains(s),
        )) {
      throw const FormatException('Invalid group receipts');
    }
    return GroupText(
      e,
      receipts: receipts,
      read: raw['read'] as bool,
      imageBytes: imageBytes,
    );
  }
}

class GroupHistory {
  const GroupHistory({
    required this.id,
    required this.title,
    required this.host,
    this.messages = const [],
    this.updated = 0,
  });
  final String id, title, host;
  final List<GroupText> messages;
  final int updated;
  int get unread => messages.where((m) => !m.read).length;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'host': host,
    'updated': updated,
    'messages': messages.map((m) => m.toJson()).toList(),
  };
  GroupHistory copy({List<GroupText>? messages, int? updated}) => GroupHistory(
    id: id,
    title: title,
    host: host,
    messages: messages ?? this.messages,
    updated: updated ?? this.updated,
  );
  static Future<GroupHistory> parse(
    Map raw, {
    bool verifySignatures = true,
  }) async {
    if (!groupIdValid(raw['id']) ||
        raw['title'] is! String ||
        (raw['title'] as String).trim().isEmpty ||
        (raw['title'] as String).length > 64 ||
        raw['host'] is! String ||
        base64Decode(raw['host'] as String).length != 32 ||
        raw['updated'] is! int ||
        (raw['updated'] as int) < 0 ||
        (raw['updated'] as int) > 8640000000000000 ||
        raw['messages'] is! List ||
        (raw['messages'] as List).length > 10000) {
      throw const FormatException('Invalid group history');
    }
    final messages = <GroupText>[];
    final keys = <String>{};
    var imageBytes = 0;
    for (final r in raw['messages'] as List) {
      final m = await GroupText.parse(
        r as Map,
        verifySignature: verifySignatures,
      );
      if (m.envelope['group'] != raw['id'] ||
          m.envelope['host'] != raw['host'] ||
          !keys.add(m.key)) {
        throw const FormatException('Conflicting group history');
      }
      messages.add(m);
      imageBytes += m.image?.length ?? 0;
      if (imageBytes > groupImageHistoryMaxBytes) {
        throw const FormatException(
          'Group image history exceeds 16 MiB. Export and delete it before continuing.',
        );
      }
    }
    return GroupHistory(
      id: raw['id'] as String,
      title: raw['title'] as String,
      host: raw['host'] as String,
      updated: raw['updated'] as int,
      messages: messages,
    );
  }
}
