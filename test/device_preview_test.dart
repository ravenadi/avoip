import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:authenticav/widgets/device_preview.dart';

// A real 4x4 JPEG so responses decode like controller frames.
final _jpeg = base64Decode('/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAABKADAAQAAAABAAAABAAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgABAAEAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A+L6KKK/lM/38P//Z');

class _RealHttp extends HttpOverrides {}

void main() {
  HttpServer? server;
  final requests = <Uri>[];

  setUp(() {
    HttpOverrides.global = _RealHttp();
    requests.clear();
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  Future<void> startServer(Future<void> Function(HttpRequest) handler) async {
    final started = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server = started;
    started.listen((req) {
      requests.add(req.uri);
      handler(req);
    });
  }

  String url(String path) => 'http://127.0.0.1:${server!.port}$path';

  Future<void> sendJpeg(HttpRequest req) async {
    req.response.headers.contentType = ContentType('image', 'jpeg');
    req.response.add(_jpeg);
    await req.response.close();
  }

  Widget tile(Widget child, {double top = 0}) {
    return MaterialApp(
      home: Stack(
        children: [
          Positioned(top: top, left: 0, width: 400, height: 225, child: child),
        ],
      ),
    );
  }

  group('PolledPreview', () {
    testWidgets('polls every second with a fresh t parameter', (tester) async {
      await tester.runAsync(() async {
        await startServer(sendJpeg);
        await tester.pumpWidget(tile(PolledPreview(url: url('/preview.jpg'))));
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      });
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
      expect(requests.length, greaterThanOrEqualTo(2));
      final stamps = requests.map((u) => u.queryParameters['t']).toList();
      expect(stamps, everyElement(isNotNull));
      expect(stamps.toSet(), hasLength(stamps.length));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('keeps the last frame and shows OFFLINE on errors',
        (tester) async {
      var calls = 0;
      await tester.runAsync(() async {
        await startServer((req) async {
          if (calls++ == 0) return sendJpeg(req);
          req.response.statusCode = 502;
          req.response.write('preview_unavailable: box unreachable');
          await req.response.close();
        });
        await tester.pumpWidget(tile(PolledPreview(url: url('/preview.jpg'))));
        await Future<void>.delayed(const Duration(milliseconds: 1600));
      });
      await tester.pump();
      expect(calls, greaterThanOrEqualTo(2));
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('OFFLINE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('does not poll while its tab is hidden', (tester) async {
      await tester.runAsync(() async {
        await startServer(sendJpeg);
        await tester.pumpWidget(
          tile(
            TickerMode(
              enabled: false,
              child: PolledPreview(url: url('/preview.jpg')),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      });
      expect(requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('does not poll while off screen', (tester) async {
      await tester.runAsync(() async {
        await startServer(sendJpeg);
        await tester.pumpWidget(
          tile(PolledPreview(url: url('/preview.jpg')), top: 2000),
        );
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      });
      expect(requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('MjpegStreamView', () {
    testWidgets('shows frames from the multipart stream', (tester) async {
      await tester.runAsync(() async {
        await startServer((req) async {
          final res = req.response;
          res.bufferOutput = false;
          res.headers.set(
            'Content-Type',
            'multipart/x-mixed-replace;boundary=boundarydonotcross',
          );
          res.add(
            utf8.encode(
              '--boundarydonotcross\r\nContent-Type: image/jpeg\r\n'
              'Content-Length: ${_jpeg.length}\r\n\r\n',
            ),
          );
          // Split the frame across chunks like a real network stream.
          res.add(_jpeg.sublist(0, 300));
          await res.flush();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          res.add(_jpeg.sublist(300));
          res.add(utf8.encode('\r\n--boundarydonotcross\r\n'));
          await res.flush();
        });
        await tester.pumpWidget(tile(MjpegStreamView(streamUrl: url('/stream'))));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.textContaining('busy'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('falls back to polling preview_url on 503', (tester) async {
      await tester.runAsync(() async {
        await startServer((req) async {
          if (req.uri.path == '/stream') {
            req.response.statusCode = 503;
            req.response.write('{"detail":"too_many_streams"}');
            await req.response.close();
          } else {
            await sendJpeg(req);
          }
        });
        await tester.pumpWidget(
          tile(
            MjpegStreamView(
              streamUrl: url('/stream'),
              previewUrl: url('/preview.jpg'),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump(); // Builds the preview fallback.
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      expect(find.textContaining('busy'), findsOneWidget);
      expect(find.byType(RawImage), findsOneWidget);
      expect(requests.where((u) => u.path == '/preview.jpg'), isNotEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('closes the stream, freeing the slot, when it goes away',
        (tester) async {
      final closed = Completer<void>();
      await tester.runAsync(() async {
        // A raw socket shows exactly when the app closes the connection
        // (HttpServer only notices once its own response ends).
        final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        raw.listen((socket) {
          var open = true;
          void markClosed([Object? _]) {
            open = false;
            if (!closed.isCompleted) closed.complete();
          }

          socket.listen((_) {}, onDone: markClosed, onError: markClosed);
          socket.done.catchError((_) {});
          socket.add(
            utf8.encode(
              'HTTP/1.1 200 OK\r\n'
              'Content-Type: multipart/x-mixed-replace;boundary=b\r\n\r\n',
            ),
          );
          () async {
            while (open) {
              try {
                socket.add(utf8.encode('--b\r\nContent-Type: image/jpeg\r\n\r\n'));
                socket.add(_jpeg);
                socket.add(utf8.encode('\r\n'));
              } catch (_) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }();
        });
        await tester.pumpWidget(
          tile(MjpegStreamView(streamUrl: 'http://127.0.0.1:${raw.port}/stream')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.byType(RawImage), findsOneWidget);
        expect(closed.isCompleted, isFalse);

        await tester.pumpWidget(const SizedBox());
        // Dispose ran inside the test's fake-async zone; pump so its queued
        // work (cancelling the subscription, closing the client) runs.
        for (var i = 0; i < 30 && !closed.isCompleted; i++) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(closed.isCompleted, isTrue);
        await raw.close();
      });
    });
  });
}
