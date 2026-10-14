import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

/// An AuthenticAV controller announcing itself on the local network.
class FoundController {
  /// Service name, e.g. "AuthenticAV Controller".
  final String name;

  /// The controller's own hostname from its TXT record, e.g. "SC1-2063".
  /// Stays the same when DHCP gives it a new IP, so it identifies it.
  final String? hostname;

  final String ip;

  /// Every IPv4 address announced by this service. [ip] remains the preferred
  /// address for callers that only need one.
  final List<String> addresses;
  final int port;

  const FoundController({
    required this.name,
    required this.hostname,
    required this.ip,
    this.addresses = const [],
    required this.port,
  });

  String get label => hostname ?? name;
}

/// Finds controllers via Bonjour / mDNS. They advertise
/// `_authenticav._tcp` with TXT `version` and `hostname`.
/// iOS needs this type in `NSBonjourServices` (Info.plist).
class ControllerDiscovery {
  static const String serviceType = '_authenticav._tcp';

  static final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  /// Browses for [timeout] and returns every controller that resolved to an
  /// IPv4 address. Returns an empty list if browsing isn't possible.
  static Future<List<FoundController>> find({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final found = <String, FoundController>{};
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? sub;
    try {
      discovery = BonsoirDiscovery(type: serviceType, printLogs: false);
      await discovery.initialize();
      final resolver = discovery.serviceResolver;
      sub = discovery.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            event.service.resolve(resolver);
          case BonsoirDiscoveryServiceResolvedEvent():
          case BonsoirDiscoveryServiceUpdatedEvent():
            final service = event.service;
            if (service != null) {
              for (final controller in _toControllers(service)) {
                found[controller.ip] = controller;
              }
            }
          default:
            break;
        }
      });
      await discovery.start();
      await Future<void>.delayed(timeout);
    } catch (e) {
      debugPrint('ControllerDiscovery: $e');
    } finally {
      await sub?.cancel();
      try {
        await discovery?.stop();
      } catch (_) {}
    }
    return found.values.toList();
  }

  static List<FoundController> _toControllers(BonsoirService service) {
    final addresses = service.hostAddresses.where(_ipv4.hasMatch).toList();
    if (addresses.isEmpty) return const [];
    final hostname = service.attributes['hostname']?.trim();
    return [
      for (final ip in addresses)
        FoundController(
          name: service.name,
          hostname: hostname == null || hostname.isEmpty ? null : hostname,
          ip: ip,
          addresses: addresses,
          port: service.port,
        ),
    ];
  }
}
