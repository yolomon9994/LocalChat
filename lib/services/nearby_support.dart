import 'package:flutter/services.dart';

enum NearbySettings { wifi, permissions, location }

enum ConnectionIssue {
  wifiOff,
  permission,
  locationOff,
  unsupported,
  busy,
  serviceStopped,
  stalePeer,
  discovery,
  connection,
  lost,
  timeout,
  security,
  settings,
  status;

  static ConnectionIssue fromCode(String? code, {bool scanning = false}) =>
      switch (code) {
        'WIFI_DISABLED' => wifiOff,
        'PERMISSION_DENIED' => permission,
        'LOCATION_DISABLED' => locationOff,
        'P2P_UNSUPPORTED' => unsupported,
        'P2P_BUSY' => busy,
        'SERVICE_STOPPED' || 'NOT_STARTED' => serviceStopped,
        'STALE_PEER' => stalePeer,
        'DISCOVERY' => discovery,
        'CONNECTION_LOST' || 'SEND_FAILED' => lost,
        'SETTINGS_UNAVAILABLE' => settings,
        _ => scanning ? discovery : connection,
      };

  String get title => switch (this) {
    wifiOff => 'Turn on Wi-Fi',
    permission => 'Allow nearby access',
    locationOff => 'Turn on Location',
    unsupported => 'Wi-Fi Direct unavailable',
    busy => 'Wi-Fi Direct is busy',
    serviceStopped => 'Restart nearby discovery',
    stalePeer => 'Find this phone again',
    discovery => 'Scan did not finish',
    connection => 'Could not connect',
    lost => 'Connection ended',
    timeout => 'Connection or verification timed out',
    security => 'Security check failed. Connection closed.',
    settings => 'Could not open settings',
    status => 'Could not check nearby access',
  };

  String get guidance => switch (this) {
    wifiOff =>
      'Enable Wi-Fi on both phones. A router or mobile data is not needed. Return here and tap Go nearby.',
    permission =>
      'In LocalChat’s Android app settings, allow Nearby devices, or Location on older Android. Return here and try again.',
    locationOff =>
      'This Android version needs the Location system switch for discovery. No location data is collected. Return here and try again.',
    unsupported =>
      'This phone cannot use Wi-Fi Direct with LocalChat. Your saved chats and drafts remain available.',
    busy =>
      'Finish or disconnect the current pairing, then scan again. If Android still reports busy, reopen LocalChat on both phones.',
    serviceStopped =>
      'Tap Go nearby again. If the Android Wi-Fi Direct service still fails, reopen LocalChat.',
    stalePeer =>
      'Scan again with LocalChat open on both phones, then select the phone from the refreshed list.',
    discovery =>
      'Keep both phones nearby with LocalChat open and Go nearby enabled. Check Wi-Fi and permissions, then scan again.',
    connection =>
      'Keep both phones nearby and accept Android’s pairing prompt on the other phone. Scan again if the device has moved away.',
    lost =>
      'Keep both apps open and phones nearby. Reconnect or scan again, then compare the new code on both phones. Unconfirmed messages need explicit Retry.',
    timeout =>
      'Keep both apps open, accept pairing and compare the code on both phones. Reconnect or scan again to start a fresh connection.',
    security =>
      'Compare every group of the fresh code in person before confirming again. If codes differ, disconnect. Queued messages stay local.',
    settings =>
      'Open Android Settings manually, then return to LocalChat and try again.',
    status =>
      'Try Check access again. Your saved chats remain available while nearby access is unavailable.',
  };

  NearbySettings? get settingsTarget => switch (this) {
    wifiOff => NearbySettings.wifi,
    permission => NearbySettings.permissions,
    locationOff => NearbySettings.location,
    _ => null,
  };

  bool get isPrerequisite =>
      this == wifiOff ||
      this == permission ||
      this == locationOff ||
      this == unsupported;
}

class NearbyStatus {
  const NearbyStatus({
    this.supported = true,
    this.wifiEnabled = true,
    this.permissionGranted = true,
    this.locationRequired = false,
    this.locationEnabled = true,
  });
  factory NearbyStatus.fromMap(Map<String, dynamic> value) => NearbyStatus(
    supported: value['supported'] == true,
    wifiEnabled: value['wifiEnabled'] == true,
    permissionGranted: value['permissionGranted'] == true,
    locationRequired: value['locationRequired'] == true,
    locationEnabled: value['locationEnabled'] == true,
  );
  final bool supported,
      wifiEnabled,
      permissionGranted,
      locationRequired,
      locationEnabled;
  ConnectionIssue? get issue => !supported
      ? ConnectionIssue.unsupported
      : !wifiEnabled
      ? ConnectionIssue.wifiOff
      : !permissionGranted
      ? ConnectionIssue.permission
      : locationRequired && !locationEnabled
      ? ConnectionIssue.locationOff
      : null;
}

abstract class NearbyTools {
  Future<NearbyStatus> check();
  Future<void> openSettings(NearbySettings target);
}

class AndroidNearbyTools implements NearbyTools {
  const AndroidNearbyTools();
  static const channel = MethodChannel('dev.localchat/transport');
  @override
  Future<NearbyStatus> check() async => NearbyStatus.fromMap(
    Map<String, dynamic>.from((await channel.invokeMethod<Map>('status'))!),
  );
  @override
  Future<void> openSettings(NearbySettings target) =>
      channel.invokeMethod<void>('openSettings', {'target': target.name});
}

class DemoNearbyTools implements NearbyTools {
  const DemoNearbyTools();
  @override
  Future<NearbyStatus> check() async => const NearbyStatus();
  @override
  Future<void> openSettings(NearbySettings target) async {}
}
