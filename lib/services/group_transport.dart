import 'package:flutter/services.dart';

abstract class GroupTransport {
  Stream<Map<String, dynamic>> get events;
  Future<void> host(String name, String title);
  Future<void> discover(String name);
  Future<void> join(String address);
  Future<void> send(String link, String frame);
  Future<void> closeLink(String link);
  Future<void> stop();
}

class WifiGroupTransport implements GroupTransport {
  static const _methods = MethodChannel('dev.localchat/groups');
  static const _events = EventChannel('dev.localchat/group_events');
  @override
  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map));
  @override
  Future<void> host(String name, String title) =>
      _methods.invokeMethod<void>('host', {'name': name, 'title': title});
  @override
  Future<void> discover(String name) =>
      _methods.invokeMethod<void>('discover', {'name': name});
  @override
  Future<void> join(String address) =>
      _methods.invokeMethod<void>('join', {'address': address});
  @override
  Future<void> send(String link, String frame) =>
      _methods.invokeMethod<void>('send', {'link': link, 'frame': frame});
  @override
  Future<void> closeLink(String link) =>
      _methods.invokeMethod<void>('close', {'link': link});
  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');
}

/// Browser controls explain the hardware requirement; no fake network promises.
class UnavailableGroupTransport implements GroupTransport {
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<void> host(String name, String title) async =>
      throw const FormatException('Use Android phones to host or join groups.');
  @override
  Future<void> discover(String name) async =>
      throw const FormatException('Use Android phones to discover groups.');
  @override
  Future<void> join(String address) async =>
      throw const FormatException('Use Android phones to join groups.');
  @override
  Future<void> send(String link, String frame) async =>
      throw StateError('No group connection');
  @override
  Future<void> closeLink(String link) async {}
  @override
  Future<void> stop() async {}
}
