import 'attachment_transfers.dart';
export 'attachment_transfers.dart' show ImageProgress;

class ImageTransfers extends AttachmentTransfers {
  ImageTransfers({
    required super.store,
    required super.peer,
    required super.canAct,
    required super.send,
    required super.enqueue,
    required super.changed,
    required super.persisted,
    super.timeout,
  }) : super(fileMode: false);
}
