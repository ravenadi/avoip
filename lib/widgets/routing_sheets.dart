import 'package:flutter/material.dart';
import '../logic/app_state.dart';
import '../models/device_model.dart';
import '../services/av_command_service.dart';
import '../theme/app_theme.dart';
import 'device_preview.dart';
import '../services/snapshot_service.dart';

// Routing sheets and snapshot recall shared by Operate and Snapshots.

Map<String, String?> get _activeRoutes => AppState.instance.activeRoutes;
List<Device> get _sources => AppState.instance.sources;
Map<String, List<Device>> get _destinationsByLocation =>
    AppState.instance.destinationsByLocation;
List<Device> get _allDestinations =>
    _destinationsByLocation.values.expand((d) => d).toList();

void _showResult(
  ScaffoldMessengerState messenger,
  bool success,
  String message,
) {
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            success ? Icons.bolt_rounded : Icons.warning_amber_rounded,
            color: Colors.black,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      backgroundColor:
          success ? Colors.greenAccent.shade400 : Colors.orangeAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    ),
  );
}

// Puts back the old route of displays the controller couldn't switch,
// unless the user has changed them again in the meantime.
void _revert(
  List<Device> failed,
  Map<String, String?> previous,
  String? attempted,
) {
  if (failed.isEmpty) return;
  for (final d in failed) {
    if (_activeRoutes[d.id] == attempted) _activeRoutes[d.id] = previous[d.id];
  }
  AppState.instance.notifyListeners();
}

String _names(List<Device> devices) => devices.map((d) => d.name).join(', ');

void _changeRoute(
  ScaffoldMessengerState messenger,
  String destId,
  String sourceId,
) {
  final source = _sources.firstWhere((s) => s.id == sourceId);
  final dest = _allDestinations.firstWhere((d) => d.id == destId);
  _routeDisplays(messenger, source, [dest]);
}

// Shows [source] on [dests]: the app updates right away, then any display
// the controller didn't confirm goes back to its previous source.
// One display → /commands/set, several → /commands/set/batch.
Future<void> _routeDisplays(
  ScaffoldMessengerState messenger,
  Device source,
  List<Device> dests,
) async {
  if (dests.isEmpty) return;
  final previous = {for (final d in dests) d.id: _activeRoutes[d.id]};
  for (final d in dests) {
    _activeRoutes[d.id] = source.id;
  }
  AppState.instance.notifyListeners();
  debugPrint(
    '[Routing] TX "${source.name}" ip=${source.ip}  →  ${dests.map((d) => '${d.name} (${d.ip})').join(', ')}',
  );

  final Set<String> failedIps;
  if (dests.length == 1) {
    final ok = await AVCommandService.routeVideo(
      txIp: source.ip,
      rxIp: dests.first.ip,
    );
    failedIps = ok ? {} : {dests.first.ip};
  } else {
    failedIps = await AVCommandService.routeBatch({
      for (final d in dests) d.ip: source.ip,
    });
  }

  final failed = dests.where((d) => failedIps.contains(d.ip)).toList();
  _revert(failed, previous, source.id);
  if (failed.isEmpty) {
    _showResult(
      messenger,
      true,
      dests.length == 1
          ? '${source.name} routed to ${dests.first.name}.'
          : '${source.name} routed to ${dests.length} displays.',
    );
  } else {
    _showResult(
      messenger,
      false,
      '${_names(failed)} didn\'t respond, so ${failed.length == 1 ? 'it keeps' : 'they keep'} the previous source.',
    );
  }
}

// Stops whatever plays on [dests], restoring the route of any display the
// controller couldn't stop.
Future<void> _stopDisplays(
  ScaffoldMessengerState messenger,
  List<Device> dests,
) async {
  if (dests.isEmpty) return;
  final previous = {for (final d in dests) d.id: _activeRoutes[d.id]};
  for (final d in dests) {
    _activeRoutes[d.id] = null;
  }
  AppState.instance.notifyListeners();

  final failed = <Device>[];
  for (final d in dests) {
    debugPrint('[Routing] stop RX "${d.name}" ip=${d.ip}');
    if (!await AVCommandService.stopRoute(rxIp: d.ip)) failed.add(d);
  }
  _revert(failed, previous, null);
  if (failed.isNotEmpty) {
    _showResult(
      messenger,
      false,
      'Couldn\'t stop ${_names(failed)}; it didn\'t respond.',
    );
  }
}

/// Lets the user pick which displays [source] should play on, then routes
/// it to the checked ones and stops it on the unchecked ones.
Future<void> showDisplayPicker(BuildContext context, Device source) {
  final messenger = ScaffoldMessenger.of(context);
  final Map<String, bool> selectedDests = {};
  for (final dest in _allDestinations) {
    selectedDests[dest.id] = _activeRoutes[dest.id] == source.id;
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder:
        (ctx) => StatefulBuilder(
          builder:
              (context, setModalState) => Container(
                height: MediaQuery.of(context).size.height * 0.8,
                decoration: const BoxDecoration(
                  color: AppTheme.backgroundLight,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Route ${source.name}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Select receivers to switch to this source',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              final toRoute = <Device>[];
                              final toStop = <Device>[];
                              for (final dest in _allDestinations) {
                                if (selectedDests[dest.id] ?? false) {
                                  toRoute.add(dest);
                                } else if (_activeRoutes[dest.id] ==
                                    source.id) {
                                  toStop.add(dest);
                                }
                              }
                              Navigator.pop(ctx);
                              _routeDisplays(messenger, source, toRoute);
                              _stopDisplays(messenger, toStop);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Apply Routes',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children:
                            _destinationsByLocation.entries.map((group) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      group.key,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueAccent,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  ...group.value.map((dest) {
                                    final isSelected =
                                        selectedDests[dest.id] ?? false;
                                    return CheckboxListTile(
                                      secondary: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox(
                                          width: 64,
                                          height: 36,
                                          child: DeviceThumbnail(device: dest),
                                        ),
                                      ),
                                      title: Text(
                                        dest.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                      subtitle: Text(
                                        dest.ip,
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      value: isSelected,
                                      activeColor: Colors.greenAccent,
                                      checkColor: Colors.black,
                                      onChanged:
                                          (val) => setModalState(
                                            () =>
                                                selectedDests[dest.id] =
                                                    val ?? false,
                                          ),
                                    );
                                  }),
                                ],
                              );
                            }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
        ),
  );
}

/// Lets the user pick the source for [destination] and routes it.
/// Returns true if a source was applied.
Future<bool> showSourcePicker(BuildContext context, Device destination) async {
  final messenger = ScaffoldMessenger.of(context);
  String? pendingSourceId = _activeRoutes[destination.id];

  final applied = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: AppTheme.backgroundLight,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade900),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Source',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentWhite,
                            ),
                          ),
                          Text(
                            'Routing to ${destination.name}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent: 140,
                          ),
                      itemCount: _sources.length,
                      itemBuilder: (context, i) {
                        final src = _sources[i];
                        final isSelected = pendingSourceId == src.id;

                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              pendingSourceId = src.id;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: AppTheme.highlightGrey,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    isSelected
                                        ? Colors.greenAccent
                                        : Colors.grey.shade800,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  DeviceThumbnail(
                                    device: src,
                                    // Keeps the name legible over the frame.
                                    overlay: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.6),
                                            Colors.black.withValues(alpha: 0.4),
                                            Colors.black.withValues(alpha: 0.8),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // The checkbox sits top-right.
                                    badgeAlignment: Alignment.topLeft,
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Checkbox(
                                      value: isSelected,
                                      activeColor: Colors.greenAccent,
                                      checkColor: Colors.black,
                                      side: const BorderSide(
                                        color: Colors.white54,
                                        width: 1.5,
                                      ),
                                      onChanged: (val) {
                                        if (val == true) {
                                          setModalState(() {
                                            pendingSourceId = src.id;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Spacer(),
                                        Text(
                                          src.name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          src.location,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade400,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade900),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          pendingSourceId != null
                              ? () {
                                _changeRoute(
                                  messenger,
                                  destination.id,
                                  pendingSourceId!,
                                );
                                Navigator.pop(ctx, true);
                              }
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.grey.shade800,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Apply Source',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  return applied ?? false;
}

/// Recalls [snapshot] on the controller (`POST /api/v1/snapshots/{id}/recall`).
/// Only the screens in the snapshot change; one screen failing doesn't stop
/// the others. The app's routes follow the screens that switched, and the
/// message names any that didn't.
Future<void> recallSnapshot(
  ScaffoldMessengerState messenger,
  ControllerSnapshot snapshot,
) async {
  final List<RecallResult> results;
  try {
    results = await SnapshotService.recall(snapshot.id);
  } on ControllerApiException catch (e) {
    _showResult(messenger, false, e.message);
    return;
  }

  final displaysById = {
    for (final d in _allDestinations)
      if (d.controllerId != null) d.controllerId!: d,
  };
  final sourcesById = {
    for (final s in _sources)
      if (s.controllerId != null) s.controllerId!: s,
  };
  String nameOf(String id) =>
      displaysById[id]?.name ??
      AppState.instance.controllerDeviceNames[id] ??
      'Unknown screen';

  var changed = false;
  final failed = <String>[];
  final skipped = <String>[];
  for (final r in results) {
    if (r.success) {
      final display = displaysById[r.rxId];
      final source = sourcesById[r.txId];
      if (display != null &&
          source != null &&
          _activeRoutes[display.id] != source.id) {
        _activeRoutes[display.id] = source.id;
        changed = true;
      }
    } else if (r.skipReason != null) {
      skipped.add(nameOf(r.rxId));
    } else {
      failed.add(nameOf(r.rxId));
    }
  }
  if (changed) AppState.instance.notifyListeners();

  final ok = results.length - failed.length - skipped.length;
  if (results.isEmpty) {
    _showResult(
      messenger,
      false,
      '"${snapshot.name}" has no screens to switch.',
    );
  } else if (failed.isEmpty && skipped.isEmpty) {
    _showResult(
      messenger,
      true,
      'Recalled "${snapshot.name}" on $ok screen${ok == 1 ? '' : 's'}.',
    );
  } else {
    _showResult(
      messenger,
      false,
      [
        'Recalled "${snapshot.name}" on $ok of ${results.length} screens.',
        if (failed.isNotEmpty) "Didn't respond: ${failed.join(', ')}.",
        if (skipped.isNotEmpty) 'Not on the network: ${skipped.join(', ')}.',
      ].join(' '),
    );
  }
}
