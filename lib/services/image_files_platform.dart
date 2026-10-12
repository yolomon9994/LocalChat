import 'package:flutter/services.dart';
import 'image_files_base.dart';

ImageFiles createImageFiles() => const AndroidImageFiles();

class AndroidImageFiles implements ImageFiles {
  const AndroidImageFiles();
  static const channel = MethodChannel('dev.localchat/images');
  @override
  Future<Uint8List?> pick() => channel.invokeMethod<Uint8List>('pick');
}
