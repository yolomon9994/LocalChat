import 'attachment_transfers.dart';

class FileTransfers extends AttachmentTransfers {
  FileTransfers({
    required super.store,
    required super.peer,
    required super.canAct,
    required super.send,
    required super.enqueue,
    required super.changed,
    required super.persisted,
    super.timeout,
  }) : super(fileMode: true);
}
