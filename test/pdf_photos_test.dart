// Photographs in the printed documents.
//
// The endorsement letter and the internal dossier both described a report's
// attachments in prose and a table and embedded no imagery at all — so the
// agency told to go and fix a pothole received a paragraph naming a barangay.
// These tests cover the preparation step, which is where every interesting
// failure lives: a private bucket's signed url, a phone photo that is 4000px
// and 4MB, a HEIC the PDF writer cannot embed, and an export that must not die
// because one download timed out.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/admin/utils/pdf_photos.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// A JPEG of [w]x[h], generated rather than fixtured so the tests can ask for
/// an oversized photo without carrying a 4MB file in the repo.
Uint8List _jpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(120, 140, 160));
  return img.encodeJpg(im, quality: 90);
}

/// Serves canned responses by url, and records what was asked for.
class _FakeClient extends http.BaseClient {
  final Map<String, http.Response> responses;
  final List<String> requested = [];
  _FakeClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    requested.add(url);
    final r = responses[url];
    if (r == null) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    return http.StreamedResponse(
      Stream.value(r.bodyBytes),
      r.statusCode,
    );
  }
}

ReportMedia _photo(String url, {bool gps = false}) => ReportMedia(
      url: url,
      mimeType: 'image/jpeg',
      source: gps ? 'camera' : 'upload',
    );

ReportMedia _video(String url) =>
    ReportMedia(url: url, mimeType: 'video/mp4');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('preparePhotos', () {
    test('fetches, decodes and numbers each photo', () async {
      final client = _FakeClient({
        'https://x/1.jpg': http.Response.bytes(_jpeg(400, 300), 200),
        'https://x/2.jpg': http.Response.bytes(_jpeg(400, 300), 200),
      });

      final out = await preparePhotos(
        [_photo('https://x/1.jpg', gps: true), _photo('https://x/2.jpg')],
        client: client,
      );

      expect(out.photos, hasLength(2));
      expect(out.failed, 0);
      expect(out.photos[0].number, 1);
      expect(out.photos[1].number, 2);
      expect(out.photos[0].gpsVerified, isTrue,
          reason: 'the GPS stamp is the difference between evidence and an '
              'illustration, and the caption prints it');
      expect(out.photos[1].gpsVerified, isFalse);
    });

    test('a large photo is downscaled, not embedded at full size', () async {
      // The reason this exists: eight 4000px phone photos would make a 40MB
      // letter to print at 240pt wide, and no mail server accepts that.
      final big = _jpeg(3000, 2000);
      final client = _FakeClient({
        'https://x/big.jpg': http.Response.bytes(big, 200),
      });

      final out =
          await preparePhotos([_photo('https://x/big.jpg')], client: client);

      expect(out.photos, hasLength(1));
      final embedded = img.decodeImage(out.photos.single.image.bytes)!;
      expect(embedded.width, lessThanOrEqualTo(900));
      expect(embedded.height, lessThanOrEqualTo(900));
      expect(out.photos.single.image.bytes.length, lessThan(big.length),
          reason: 'the embedded copy must be smaller than the original');
    });

    test('a small photo is not upscaled', () async {
      final client = _FakeClient({
        'https://x/s.jpg': http.Response.bytes(_jpeg(120, 90), 200),
      });

      final out =
          await preparePhotos([_photo('https://x/s.jpg')], client: client);

      final embedded = img.decodeImage(out.photos.single.image.bytes)!;
      expect(embedded.width, 120);
      expect(embedded.height, 90);
    });

    test('videos are counted, never fetched', () async {
      final client = _FakeClient({
        'https://x/1.jpg': http.Response.bytes(_jpeg(200, 200), 200),
      });

      final out = await preparePhotos(
        [_photo('https://x/1.jpg'), _video('https://x/clip.mp4')],
        client: client,
      );

      expect(out.photos, hasLength(1));
      expect(out.videos, 1);
      expect(client.requested, ['https://x/1.jpg'],
          reason: 'downloading a video to throw it away wastes the officer\'s '
              'time on a mobile connection');
    });

    test('a failed download drops that photo and keeps the rest', () async {
      // The whole point of the degrade path: a dossier missing one photo beats
      // an export that throws because one signed url had expired.
      final client = _FakeClient({
        'https://x/ok.jpg': http.Response.bytes(_jpeg(200, 200), 200),
        'https://x/gone.jpg': http.Response.bytes(Uint8List(0), 403),
      });

      final out = await preparePhotos(
        [_photo('https://x/ok.jpg'), _photo('https://x/gone.jpg')],
        client: client,
      );

      expect(out.photos, hasLength(1));
      expect(out.failed, 1);
      expect(out.photos.single.number, 1);
    });

    test('undecodable bytes are dropped rather than thrown', () async {
      final client = _FakeClient({
        'https://x/junk.jpg': http.Response.bytes(
          Uint8List.fromList(utf8.encode('this is not an image')),
          200,
        ),
      });

      final out =
          await preparePhotos([_photo('https://x/junk.jpg')], client: client);

      expect(out.photos, isEmpty);
      expect(out.failed, 1);
    });

    test('photo numbers follow the attachment list, videos included',
        () async {
      // "Photo 3" in a caption has to mean the same row as "3" in the
      // attachments table, or the two halves of the document disagree.
      final client = _FakeClient({
        'https://x/b.jpg': http.Response.bytes(_jpeg(200, 200), 200),
      });

      final out = await preparePhotos(
        [_video('https://x/a.mp4'), _photo('https://x/b.jpg')],
        client: client,
      );

      expect(out.photos.single.number, 2,
          reason: 'the video occupies position 1 in the attachment list');
    });

    test('the cap limits downloads and reports the remainder', () async {
      final responses = <String, http.Response>{
        for (var i = 0; i < 6; i++)
          'https://x/$i.jpg': http.Response.bytes(_jpeg(100, 100), 200),
      };
      final client = _FakeClient(responses);

      final out = await preparePhotos(
        [for (var i = 0; i < 6; i++) _photo('https://x/$i.jpg')],
        limit: 4,
        client: client,
      );

      expect(out.photos, hasLength(4));
      expect(out.failed, 2, reason: 'the page has to be able to say so');
      expect(client.requested, hasLength(4),
          reason: 'photos past the cap must not be downloaded at all');
    });

    test('no media at all is not an error', () async {
      final out = await preparePhotos(const [], client: _FakeClient({}));
      expect(out.isEmpty, isTrue);
      expect(out.failed, 0);
      expect(out.videos, 0);
    });
  });

  group('pdfPhotoPlates', () {
    test('renders nothing extra for an empty set with no heading', () {
      // The letter passes no heading: a letter that announces an enclosure it
      // does not have is simply wrong, so it emits nothing at all.
      final out = pdfPhotoPlates(PreparedPhotos.empty);
      expect(out, hasLength(1),
          reason: 'just the "no photographs" note for the dossier');
    });

    test('an empty set still gets a heading when one is asked for', () {
      final out = pdfPhotoPlates(PreparedPhotos.empty, heading: '6. Photos');
      expect(out, hasLength(2), reason: 'heading plus the note');
    });

    test('rows hold two photos each, so an odd count still grids', () async {
      final client = _FakeClient({
        for (var i = 0; i < 5; i++)
          'https://x/$i.jpg': http.Response.bytes(_jpeg(100, 100), 200),
      });
      final prepared = await preparePhotos(
        [for (var i = 0; i < 5; i++) _photo('https://x/$i.jpg')],
        client: client,
      );

      final out = pdfPhotoPlates(prepared);
      // 5 photos -> 3 rows. No heading, and nothing failed, so no trailing note.
      expect(out, hasLength(3));
    });

    test('the heading travels with the first row of plates', () async {
      // Found by LOOKING at a rendered letter: page one ended with
      // "Enclosures: 4 photographs submitted by the reporting citizen" and page
      // two opened with four unannounced pictures. MultiPage breaks only
      // BETWEEN children, so a heading emitted as its own child can be orphaned
      // exactly like the signature block was before it.
      //
      // The heading must therefore NOT be a top-level child of its own.
      final client = _FakeClient({
        for (var i = 0; i < 4; i++)
          'https://x/$i.jpg': http.Response.bytes(_jpeg(100, 100), 200),
      });
      final prepared = await preparePhotos(
        [for (var i = 0; i < 4; i++) _photo('https://x/$i.jpg')],
        client: client,
      );

      final out = pdfPhotoPlates(prepared, heading: '6. Photographs');

      // 4 photos -> 2 rows, and the heading is folded INTO the first, so the
      // list is 2 long rather than 3.
      expect(out, hasLength(2),
          reason: 'a heading emitted as its own child can be page-broken away '
              'from the photographs it introduces');
    });

    test('an unprintable attachment is stated, not silently dropped', () async {
      final client = _FakeClient({
        'https://x/ok.jpg': http.Response.bytes(_jpeg(100, 100), 200),
        'https://x/bad.jpg': http.Response.bytes(Uint8List(0), 500),
      });
      final prepared = await preparePhotos(
        [
          _photo('https://x/ok.jpg'),
          _photo('https://x/bad.jpg'),
          _video('https://x/c.mp4'),
        ],
        client: client,
      );

      final out = pdfPhotoPlates(prepared);
      // One row of plates, plus the line accounting for what is missing.
      expect(out, hasLength(2),
          reason: 'showing 1 photo where the table lists 3 invites the reader '
              'to assume the others do not exist');
    });
  });
}
