import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/feedback_photos.dart';

void main() {
  group('FeedbackPhotos.pathOf', () {
    test('strips a legacy public URL down to the object key', () {
      expect(
        FeedbackPhotos.pathOf(
          'https://vxvflhjbafqwehuxnmeq.supabase.co/storage/v1/object/public/'
          'feedback-assets/feedback/384dfd84-efad-488a-8632-5b46e3fbf3d7/1784087487167.jpg',
        ),
        'feedback/384dfd84-efad-488a-8632-5b46e3fbf3d7/1784087487167.jpg',
      );
    });

    test('drops a query string and decodes escapes', () {
      expect(
        FeedbackPhotos.pathOf(
          'https://x.supabase.co/storage/v1/object/public/feedback-assets/'
          'feedback/a%20b/1.jpg?t=1',
        ),
        'feedback/a b/1.jpg',
      );
    });

    test('leaves a stored path untouched', () {
      expect(FeedbackPhotos.pathOf('feedback/abc/1.webp'), 'feedback/abc/1.webp');
    });
  });

  group('FeedbackPhotos.newUploadPath', () {
    test('carries no user id and is unique per call', () {
      final a = FeedbackPhotos.newUploadPath('jpg');
      final b = FeedbackPhotos.newUploadPath('jpg');
      expect(a, matches(RegExp(r'^feedback/[0-9a-f]{32}/\d+\.jpg$')));
      expect(a, isNot(b));
    });
  });
}
