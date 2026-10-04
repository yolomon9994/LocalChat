import 'package:flutter/services.dart';

abstract class Transport {
  Stream<Map<String, dynamic>> get events;
  Future<void> start(String name);
  Future<void> scan();
  Future<void> connect(String address);
  Future<void> send(String frame);
  Future<void> disconnect();
  Future<void> stop();
}

class WifiDirectTransport implements Transport {
  static const _methods = MethodChannel('dev.localchat/transport');
  static const _events = EventChannel('dev.localchat/events');
  @override
  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));
  @override
  Future<void> start(String name) =>
      _methods.invokeMethod<void>('start', {'name': name});
  @override
  Future<void> scan() => _methods.invokeMethod<void>('scan');
  @override
  Future<void> connect(String address) =>
      _methods.invokeMethod<void>('connect', {'address': address});
  @override
  Future<void> send(String frame) =>
      _methods.invokeMethod<void>('send', {'frame': frame});
  @override
  Future<void> disconnect() => _methods.invokeMethod<void>('disconnect');
  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');
}
