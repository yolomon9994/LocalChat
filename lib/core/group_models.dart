import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'secure_session.dart';
import 'chat_image.dart';
import 'chat_file.dart';
import 'message_reply.dart';

const groupLimit = 8; // Host plus seven guests; hardware may support fewer.
const groupImageHistoryMaxBytes = 16 * 1024 * 1024;
const groupAttachmentHistoryMaxBytes = groupImageHistoryMaxBytes;
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
    this.supportsFiles = false,
    this.supportsReplies = false,
  });
  final String id, name, public;
  final bool supportsImages;
  final bool supportsFiles;
  final bool supportsReplies;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'public': public,
    'images': supportsImages,
    'files': supportsFiles,
    'replies': supportsReplies,
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
        (raw.containsKey('images') && raw['images'] is! bool) ||
        (raw.containsKey('files') && raw['files'] is! bool) ||
        (raw.containsKey('replies') && raw['replies'] is! bool)) {
      throw const FormatException('Invalid group member');
    }
    return GroupMember(
      raw['id'] as String,
      name,
      public,
      supportsImages: raw['images'] == true,
      supportsFiles: raw['files'] == true,
      supportsReplies: raw['replies'] == true,
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
    this.fileBytes,
  });
  final Map<String, dynamic> envelope;
  final Map<String, String> receipts;
  final bool read;
  final Uint8List? imageBytes;
  final Uint8List? fileBytes;
  ChatFile? get file =>
      envelope.containsKey('file') ? ChatFile.parse(envelope['file']) : null;
  ChatImage? get image =>
      envelope.containsKey('image') ? ChatImage.parse(envelope['image']) : null;
  MessageReply? get reply => envelope.containsKey('reply')
      ? MessageReply.parse(envelope['reply'], group: true)
      : null;
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
    Uint8List? fileBytes,
  }) => GroupText(
    envelope,
    receipts: receipts ?? this.receipts,
    read: read ?? this.read,
    imageBytes: imageBytes ?? this.imageBytes,
    fileBytes: fileBytes ?? this.fileBytes,
  );
  Map<String, Object?> toJson() => {
    'envelope': envelope,
    'receipts': receipts,
    'read': read,
    if (image != null && imageBytes != null)
      'imageData': base64Encode(imageBytes!),
    if (file != null && fileBytes != null) 'fileData': base64Encode(fileBytes!),
  };
  static List<int> _bytes(Map e) => utf8.encode(
    jsonEncode([
      e.containsKey('reply')
          ? 'LocalChat/group-reply/1'
          : e.containsKey('file')
          ? 'LocalChat/group-file/1'
          : e.containsKey('image')
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
      if (e.containsKey('reply'))
        MessageReply.parse(e['reply'], group: true).toJson(),
      if (e.containsKey('image')) ChatImage.parse(e['image']).toJson(),
      if (e.containsKey('file')) ChatFile.parse(e['file']).toJson(),
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
    Uint8List? fileBytes,
    String? fileName,
    MessageReply? reply,
  }) async {
    if (imageBytes != null && fileBytes != null) {
      throw const FormatException('Choose one attachment type');
    }
    if (reply != null) {
      MessageReply.parse(reply.toJson(), group: true);
      if (imageBytes != null || fileBytes != null) {
        throw const FormatException('Replies are text only');
      }
    }
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
      if (reply != null) 'reply': reply.toJson(),
      'targets': [...targets]..sort(),
      if (imageBytes != null)
        'image': (await ChatImage.fromBytes(imageBytes)).toJson(),
      if (fileBytes != null)
        'file': (await ChatFile.fromBytes(
          fileName ?? 'attachment.bin',
          fileBytes,
        )).toJson(),
    };
    e['signature'] = base64Encode(
      (await Ed25519().sign(_bytes(e), keyPair: identity)).bytes,
    );
    return GroupText(
      e,
      read: true,
      receipts: {for (final id in targets) id: 'pending'},
      imageBytes: imageBytes == null ? null : Uint8List.fromList(imageBytes),
      fileBytes: fileBytes == null ? null : Uint8List.fromList(fileBytes),
    );
  }

  static Future<GroupText> parse(
    Map raw, {
    bool verifySignature = true,
    bool requireImageData = true,
    bool requireFileData = true,
  }) async {
    if (raw['envelope'] is! Map ||
        raw['receipts'] is! Map ||
        raw['read'] is! bool) {
      throw const FormatException('Invalid group record');
    }
    final e = Map<String, dynamic>.from(raw['envelope'] as Map);
    final image = e.containsKey('image') ? ChatImage.parse(e['image']) : null;
    final file = e.containsKey('file') ? ChatFile.parse(e['file']) : null;
    if (e.containsKey('reply')) {
      MessageReply.parse(e['reply'], group: true);
      if (image != null || file != null) {
        throw const FormatException('Replies are text only');
      }
    }
    if ((image != null && file != null) ||
        (file != null && e['text'] != 'File') ||
        (file == null && raw.containsKey('fileData'))) {
      throw const FormatException('Invalid group file record');
    }
    Uint8List? fileBytes;
    if (file != null && (requireFileData || raw.containsKey('fileData'))) {
      final encoded = raw['fileData'];
      if (encoded is! String ||
          encoded.length > ((fileMaxBytes + 2) ~/ 3) * 4) {
        throw const FormatException('Invalid group file contents');
      }
      fileBytes = base64Decode(encoded);
      await file.verify(fileBytes);
    }
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
      fileBytes: fileBytes,
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
    this.pinned = false,
    this.archived = false,
  });
  final String id, title, host;
  final List<GroupText> messages;
  final int updated;
  final bool pinned, archived;
  int get unread => messages.where((m) => !m.read).length;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'host': host,
    'updated': updated,
    'messages': messages.map((m) => m.toJson()).toList(),
    if (pinned || archived) ...{'pinned': pinned, 'archived': archived},
  };
  GroupHistory copy({
    List<GroupText>? messages,
    int? updated,
    bool? pinned,
    bool? archived,
  }) => GroupHistory(
    id: id,
    title: title,
    host: host,
    messages: messages ?? this.messages,
    updated: updated ?? this.updated,
    pinned: pinned ?? this.pinned,
    archived: archived ?? this.archived,
  );
  static Future<GroupHistory> parse(
    Map raw, {
    bool verifySignatures = true,
  }) async {
    if (raw.containsKey('pinned') && raw['pinned'] is! bool ||
        raw.containsKey('archived') && raw['archived'] is! bool ||
        !groupIdValid(raw['id']) ||
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
      imageBytes += (m.image?.length ?? 0) + (m.file?.length ?? 0);
      if (imageBytes > groupAttachmentHistoryMaxBytes) {
        throw const FormatException(
          'Group attachment history exceeds 16 MiB. Export and delete it before continuing.',
        );
      }
    }
    return GroupHistory(
      id: raw['id'] as String,
      title: raw['title'] as String,
      host: raw['host'] as String,
      updated: raw['updated'] as int,
      pinned: raw['pinned'] as bool? ?? false,
      archived: raw['archived'] as bool? ?? false,
      messages: messages,
    );
  }
}

/// Pins are local organization; activity and ID provide stable order within it.
int compareGroupHistories(GroupHistory a, GroupHistory b) {
  if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
  final activity = b.updated.compareTo(a.updated);
  return activity != 0 ? activity : a.id.compareTo(b.id);
}
