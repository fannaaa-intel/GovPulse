import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

/// Image provider for a just-picked file, correct on every platform.
///
/// On web an [XFile.path] is a `blob:` URL, not a filesystem path, and every
/// `dart:io` File operation throws `Unsupported operation: _Namespace`. That is
/// what crashed the attachment previews with:
///
///   "Image.file is not supported on Flutter Web. Consider using either
///    Image.asset or Image.network instead."
///
/// Native platforms keep [FileImage]; web reads the blob through [NetworkImage],
/// which handles `blob:` URLs.
///
/// Lives here rather than in a screen because both the Report and Suggestion
/// attachment pickers need it — they are near-identical code, and this bug was
/// originally fixed in only one of them.
///
/// Video has the same constraint: `VideoPlayerController.file` must become
/// `VideoPlayerController.networkUrl(Uri.parse(file.path))` under [kIsWeb]. That
/// is done inline at each call site rather than wrapped here, so this file stays
/// free of a `video_player` dependency.
ImageProvider pickedImageProvider(XFile file) =>
    kIsWeb ? NetworkImage(file.path) : FileImage(File(file.path));
