import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_colors.dart';
import '../../../providers/community_posts_provider.dart';
import 'news_feed_helpers.dart';
import 'comment_item.dart';
import 'comment_post_recap.dart';
import 'edit_comment_sheet.dart';
import '../../app_snackbar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../app_dialog.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../theme/mobile_metrics.dart';

// The width this file's `width * 0.xx` sizing is proportioned against is a
// FIXED base, not the viewport: these sheets are full-bleed, so on a landscape
// phone the raw viewport width (~844) would scale every icon, radius and pad to
// roughly double — against a screen that is only ~390dp tall. The sheet still
// spans the display; only its proportions stop chasing the display's width.
//
// That base is `kThreadMetrics`, which now lives beside the rows it sizes in
// comment_item.dart, so the feed card's inline comment preview can size itself
// the same way without importing this sheet.

/// Sizing base for the two modal sheets that ACT on the thread — edit a
/// comment, confirm a delete — as opposed to the thread itself, which uses
/// [kThreadMetrics] directly.
///
/// ── Why web is pinned to [kThreadMetrics] ─────────────────────────────────
/// On a phone this clamp lands near the real viewport, so these sheets come out
/// at roughly the same scale as the 400-wide thread they were opened from. In a
/// browser the viewport is always wider than 480, so the clamp resolves to its
/// CEILING every time and the sheets draw at the largest phone size that
/// exists — 480 — over a thread that has already come down to 400. Same defect
/// [_CategoryModal] and [_HotlineRow] had in emergency_screen: the host got a
/// smaller web number and the surfaces inside it kept the ceiling.
///
/// Reusing [kThreadMetrics] rather than inventing a second number is the whole
/// point of that constant: one fixed base, so the thread and the sheets that
/// edit it cannot disagree about how big a comment is.
///
/// Mobile is untouched — `kIsWeb` is a compile-time false there, so the app
/// compiles to exactly the expression that was here before.
double _sizingWidth(BuildContext context) =>
    kIsWeb ? kThreadMetrics : uiScaleWidth(context);

/// Opens [post]'s comment thread in the presentation that matches the viewport:
/// a centred dialog on wide screens, the phone bottom sheet below that.
///
/// Every surface that shows this thread (citizen news feed, staff community
/// feed) goes through here — presenting CommentsSheet directly is what left the
/// staff console showing a bottom sheet on desktop while admin showed a dialog.
Future<void> showCommentsSheet(
  BuildContext context, {
  required Map<String, dynamic> post,
  required Set<String> likedComments,
  required ValueChanged<String> onToggleLike,
  String? highlightCommentId,
  String? initialReplyTo,
  String? officialName,
}) {
  final wide = MediaQuery.of(context).size.width >= kCommentsDialogBreakpoint;

  CommentsSheet sheet({required bool asDialog}) => CommentsSheet(
    post: post,
    likedComments: likedComments,
    onToggleLike: onToggleLike,
    highlightCommentId: highlightCommentId,
    initialReplyTo: initialReplyTo,
    asDialog: asDialog,
    officialName: officialName,
  );

  if (wide) {
    // Size and insets come from news_feed_helpers so this dialog, the admin
    // console's and the staff console's stay the same shape — and so the
    // web's Facebook-parity proportions are stated in one place. Everything is
    // clamped against the viewport, never fixed: the old fixed 560x720 inside
    // a 24px inset needed 608x768 to draw, which clipped the composer off the
    // bottom on exactly the 1366x768 laptops these consoles run on.
    final size = MediaQuery.of(context).size;
    return showAppDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: kCommentsDialogHorizontalInset,
          vertical: commentsDialogVerticalInset(size),
        ),
        child: ConstrainedBox(
          constraints: commentsDialogConstraints(size),
          child: sheet(asDialog: true),
        ),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => sheet(asDialog: false),
  );
}

class CommentsSheet extends StatefulWidget {
  final Map<String, dynamic> post;
  final String? initialReplyTo;
  final Set<String> likedComments;
  final ValueChanged<String> onToggleLike;

  /// Comment (or reply) id to land on when the sheet opens from a notification:
  /// its thread is auto-expanded, scrolled into view and flashed blue, so the
  /// tap goes to THE comment rather than just the post.
  final String? highlightCommentId;

  /// Presentation mode. False (default) is the phone bottom sheet: drag handle,
  /// rounded top only, height driven by DraggableScrollableSheet. True is the
  /// wide-screen centred dialog — no handle, rounded all round, height supplied
  /// by the Dialog's constraints. Set by [showCommentsSheet], which picks the
  /// mode from the width so admin, staff and citizen all present alike.
  final bool asDialog;

  /// Non-null puts the sheet in OFFICIAL mode, for the admin/staff consoles:
  /// the header drops its count, the composer names the identity behind a
  /// filled send button, and each comment gets the admin panel's full-width
  /// bubble, LGU chip and Edit/Delete text actions.
  ///
  /// The name is the identity the official is posting under (e.g. "LGU
  /// Aparri"), so the composer says who the comment will come from — a console
  /// user is acting for the LGU, not themselves, and that is worth stating.
  /// Null (the citizen feed) leaves every one of those untouched.
  final String? officialName;

  const CommentsSheet({
    super.key,
    required this.post,
    this.asDialog = false,
    this.initialReplyTo,
    this.officialName,
    required this.likedComments,
    required this.onToggleLike,
    this.highlightCommentId,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  late final TextEditingController _inputController;
  late final FocusNode _inputFocus;

  String? _replyingTo;
  String? _replyingToParentId;
  String? _replyingToUserId;
  final Set<String> _expandedReplies = {};
  bool _sending = false;

  // ── Notification deep-link: flash the target comment's thread blue ────────
  final GlobalKey _highlightBlockKey = GlobalKey();
  bool _highlightFlash = false;
  bool _highlightConsumed = false;
  String? _myPhotoUrl;
  String? _myPhotoPath;
  String? _myDisplayName;

  final SupabaseClient _supabase = Supabase.instance.client;
  String? get _currentUserId => _supabase.auth.currentUser?.id;

  // ── Presentation ───────────────────────────────────────────────────────────
  //
  // The ADMIN console's comment thread is the reference for all three surfaces.
  // Citizen, staff and admin draw it identically: a plain "Comments" header,
  // full-width bubbles, an LGU chip on official authors, Edit/Delete as text
  // actions, and a filled send disc. Nothing here branches on who is looking.
  //
  // Only the SHELL varies, and only by viewport — a centred dialog at/above
  // [kCommentsDialogBreakpoint], the slide-up bottom sheet below it and in the
  // app. That split lives in [showCommentsSheet], not here.
  //
  // [CommentsSheet.officialName] is a separate axis and does NOT gate any of
  // the above: it only names the identity in the composer, which is an
  // official-only idea — a citizen comments as themselves.

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _inputFocus = FocusNode();
    _inputFocus.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.initialReplyTo != null) {
      _setReplyByAuthorName(widget.initialReplyTo!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
    _loadMyPhoto();
    CommunityPostsProvider.instance.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    CommunityPostsProvider.instance.removeListener(_onProviderChanged);
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMyPhoto() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final res = await _supabase
          .from('citizen_details')
          .select('profile_photo_path')
          .eq('user_id', userId)
          .maybeSingle();
      final path = res?['profile_photo_path'] as String?;
      if (path == null || path.isEmpty) {
        // Not a citizen. Officials (admin role 1 / staff role 2) keep their
        // name + avatar in admin_profiles, and have no citizen_details row at
        // all — so bailing here is what left the composer showing the grey
        // silhouette and signing optimistic comments "You" for every staff and
        // admin account. Their own row is readable via staff_reads_own_profile.
        await _loadMyOfficialPhoto(userId);
        return;
      }

      if (!mounted) return;
      final nameRes = await _supabase
          .from('public_user_profiles')
          .select('first_name, last_name')
          .eq('user_id', userId)
          .maybeSingle();
      final first = (nameRes?['first_name'] as String?) ?? '';
      final last = (nameRes?['last_name'] as String?) ?? '';
      final full = '$first $last'.trim();
      setState(() {
        _myPhotoPath = path;
        _myPhotoUrl = _supabase.storage
            .from('profile-photos')
            .getPublicUrl(path);
        _myDisplayName = full.isNotEmpty ? full : null;
      });
    } catch (_) {}
  }

  /// Official (admin/staff) fallback for [_loadMyPhoto]. `photo_url` here is a
  /// full public URL from the `admin-avatars` bucket, not a storage path, so it
  /// is used as-is and cache-keyed on itself.
  Future<void> _loadMyOfficialPhoto(String userId) async {
    try {
      final row = await _supabase
          .from('admin_profiles')
          .select('full_name, photo_url')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted || row == null) return;
      final url = (row['photo_url'] as String?)?.trim();
      final name = (row['full_name'] as String?)?.trim();
      if ((url == null || url.isEmpty) && (name == null || name.isEmpty)) {
        return;
      }
      setState(() {
        _myPhotoPath = null; // URL is already absolute — no path to key on
        if (url != null && url.isNotEmpty) _myPhotoUrl = url;
        if (name != null && name.isNotEmpty) _myDisplayName = name;
      });
    } catch (_) {
      /* RLS / offline — composer just keeps the silhouette */
    }
  }

  /// The post as the provider currently holds it — single source of truth.
  ///
  /// [CommentsSheet.post] is the snapshot the caller had when the sheet opened,
  /// so its likes and commentCount freeze the moment you open the thread. The
  /// recap header must not quote a stale count while you watch the comment you
  /// just posted appear below it.
  Map<String, dynamic> _livePost() =>
      CommunityPostsProvider.instance.sortedPosts.firstWhere(
        (p) => p['id'] == widget.post['id'],
        orElse: () => widget.post,
      );

  // Always reads from the provider — single source of truth.
  // The provider's sortedPosts already merges optimistic (isSending) comments.
  List<Map<String, dynamic>> _getComments() {
    final raw = List<Map<String, dynamic>>.from(
      (_livePost()['comments'] as List<dynamic>).cast<Map<String, dynamic>>(),
    );
    raw.sort((a, b) {
      final ta = a['timestamp'] as DateTime?;
      final tb = b['timestamp'] as DateTime?;
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta); // newest first
    });
    return raw;
  }

  void _setReplyByAuthorName(String authorName) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final comments = _getComments();

    for (final cm in comments) {
      if (cm['author'] == authorName) {
        final isSelf = currentUserId != null && cm['authorId'] == currentUserId;
        setState(() {
          _replyingTo = isSelf ? 'yourself' : authorName;
          _replyingToParentId = cm['id'] as String;
          _replyingToUserId = isSelf ? null : cm['authorId'] as String?;
        });
        return;
      }
      final replies = (cm['replies'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      for (final rm in replies) {
        if (rm['author'] == authorName) {
          final isSelf =
              currentUserId != null && rm['authorId'] == currentUserId;
          setState(() {
            _replyingTo = isSelf ? 'yourself' : authorName;
            _replyingToParentId = cm['id'] as String;
            _replyingToUserId = isSelf ? null : rm['authorId'] as String?;
          });
          return;
        }
      }
    }
    setState(() {
      _replyingTo = authorName;
      _replyingToParentId = null;
      _replyingToUserId = null;
    });
  }

  void _setReplyByCommentId(String commentId, String authorName) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final comments = _getComments();

    for (final cm in comments) {
      if (cm['id'] == commentId) {
        final isSelf = currentUserId != null && cm['authorId'] == currentUserId;
        setState(() {
          _replyingTo = isSelf ? 'yourself' : authorName;
          _replyingToParentId = cm['id'] as String;
          _replyingToUserId = isSelf ? null : cm['authorId'] as String?;
        });
        return;
      }
      final replies = (cm['replies'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      for (final rm in replies) {
        if (rm['id'] == commentId) {
          final isSelf =
              currentUserId != null && rm['authorId'] == currentUserId;
          setState(() {
            _replyingTo = isSelf ? 'yourself' : authorName;
            _replyingToParentId = cm['id'] as String;
            _replyingToUserId = isSelf ? null : rm['authorId'] as String?;
          });
          return;
        }
      }
    }
  }

  void _cancelReply() => setState(() {
    _replyingTo = null;
    _replyingToParentId = null;
    _replyingToUserId = null;
  });

  void _toggleExpandReplies(String id) {
    setState(
      () => _expandedReplies.contains(id)
          ? _expandedReplies.remove(id)
          : _expandedReplies.add(id),
    );
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      showAppSnackBar(
        context,
        "Your session has expired. Please log in again.",
        type: AppSnackType.error,
      );
      return;
    }

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticComment = <String, dynamic>{
      'id': tempId,
      'postId': widget.post['id'],
      'parentId': _replyingToParentId,
      'authorId': userId,
      // Officials comment AS their office, so the optimistic bubble must carry
      // that name too — [_myDisplayName] is the person behind the account, and
      // showing it here made a staff comment read under their own name for the
      // second before the server row replaced it.
      'author': widget.officialName ?? _myDisplayName ?? 'You',
      'authorPhotoUrl': _myPhotoUrl,
      'authorPhotoPath': _myPhotoPath,
      'mentionedUser': null,
      'mentionedUserId': _replyingToUserId,
      // Officials keep their LGU chip while the comment is still in flight.
      // Without this the chip only appeared after the reconcile, so a staff
      // member's own comment read as a citizen's for a second or two.
      'isOfficial': widget.officialName != null,
      'text': text,
      'likes': 0,
      'timestamp': DateTime.now(),
      'replies': <Map<String, dynamic>>[],
      'isSending': true,
    };

    final postId = widget.post['id'] as String;

    // Push into provider — survives sheet close/reopen
    CommunityPostsProvider.instance.addOptimisticComment(
      postId,
      optimisticComment,
    );

    setState(() {
      _replyingTo = null;
      _replyingToParentId = null;
      _replyingToUserId = null;
      _sending = true;
    });
    _inputController.clear();

    try {
      final inserted = await _supabase
          .from('community_comments')
          .insert({
            'post_id': postId,
            'parent_comment_id': optimisticComment['parentId'],
            'author_id': userId,
            'mentioned_user_id': optimisticComment['mentionedUserId'],
            'body': text,
          })
          .select('id')
          .single();
      final realId = inserted['id'] as String;
      // DB confirmed — record real id so reconciliation is id-based, not text-based
      if (mounted) {
        CommunityPostsProvider.instance.confirmOptimisticComment(
          postId,
          tempId,
          realId,
        );
      }
    } catch (e) {
      // Remove optimistic on failure
      CommunityPostsProvider.instance.removeOptimisticComment(postId, tempId);
      if (mounted) {
        if (e is PostgrestException &&
            (e.hint ?? '') == 'rate_limit_exceeded') {
          showAppSnackBar(
            context,
            "You're commenting too fast. Please wait a moment before trying again.",
            type: AppSnackType.error,
          );
        } else {
          showAppSnackBar(
            context,
            "Could not send your comment. Please try again.",
            type: AppSnackType.error,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handleEditComment(Map<String, dynamic> entry) async {
    final id = entry['id'] as String;
    final currentText = (entry['text'] as String?) ?? '';
    final width = _sizingWidth(context);

    final newText = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.06)),
      ),
      builder: (ctx) =>
          EditCommentSheet(initialText: currentText, width: width),
    );

    if (newText == null ||
        newText.trim().isEmpty ||
        newText.trim() == currentText) {
      return;
    }
    final trimmed = newText.trim();
    final postId = widget.post['id'] as String;

    // Optimistically update AND mark as sending to block realtime overwrites
    CommunityPostsProvider.instance.updateOptimisticCommentText(
      postId,
      id,
      trimmed,
      markAsSending: true, // <-- add this flag
    );

    try {
      await _supabase
          .from('community_comments')
          .update({'body': trimmed})
          .eq('id', id);

      // Confirmed — unmark sending so realtime can resume normally
      if (mounted) {
        CommunityPostsProvider.instance.updateOptimisticCommentText(
          postId,
          id,
          trimmed,
          markAsSending: false,
        );
      }
    } catch (e) {
      if (mounted) {
        CommunityPostsProvider.instance.updateOptimisticCommentText(
          postId,
          id,
          currentText,
          markAsSending: false, // roll back and unblock
        );
        showAppSnackBar(
          context,
          "Could not edit your comment. Please try again.",
          type: AppSnackType.error,
        );
      }
    }
  }

  Future<void> _handleDeleteComment(Map<String, dynamic> entry) async {
    final id = entry['id'] as String;
    final width = _sizingWidth(context);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.06)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, width * 0.025, 0, width * 0.04),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              dragHandle(width),
              Container(
                width: width * 0.18,
                height: width * 0.18,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: width * 0.09,
                  color: const Color(0xFFEF4444),
                ),
              ),
              SizedBox(height: width * 0.04),
              Text(
                'Delete Comment?',
                style: TextStyle(
                  fontSize: width * 0.048,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F2937),
                ),
              ),
              SizedBox(height: width * 0.02),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: width * 0.1),
                child: Text(
                  'This comment will be permanently removed and cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: width * 0.034,
                    color: const Color(0xFF6B7280),
                    height: 1.45,
                  ),
                ),
              ),
              SizedBox(height: width * 0.05),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: width * 0.05),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, false),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            vertical: width * 0.038,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(width * 0.035),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: width * 0.038,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF374151),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: width * 0.03),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx, true),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            vertical: width * 0.038,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(width * 0.035),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.delete_rounded,
                                color: Colors.white,
                                size: width * 0.042,
                              ),
                              SizedBox(width: width * 0.015),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  fontSize: width * 0.038,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    FocusManager.instance.primaryFocus?.unfocus();

    final loaderNavigator = Navigator.of(context);

    showAppDialog(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => const Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );

    try {
      final isTopLevel = entry['parentId'] == null;
      if (isTopLevel) {
        await _supabase
            .from('community_comments')
            .delete()
            .eq('parent_comment_id', id);
      }
      await _supabase.from('community_comments').delete().eq('id', id);

      if (mounted) {
        loaderNavigator.pop();
        final postId = widget.post['id'] as String;
        final replyCount = isTopLevel
            ? ((entry['replies'] as List<dynamic>?)?.length ?? 0)
            : 0;
        final deleteCount = 1 + replyCount;

        CommunityPostsProvider.instance.purgeOptimisticByAnyId(
          postId,
          id,
          alsoChildren: isTopLevel,
        );
        CommunityPostsProvider.instance.removeCommentFromPost(
          postId,
          id,
          isTopLevel: isTopLevel,
        );
        CommunityPostsProvider.instance.decrementCommentCount(
          postId,
          deleteCount,
        );
        // Provider notifyListeners() already triggers _onProviderChanged → setState,
        // but call explicitly in case the widget is not yet listening after pop.
        if (mounted) setState(() {});
      }
    } catch (_) {
      if (mounted) {
        loaderNavigator.pop();
        showAppSnackBar(
          context,
          "Could not delete your comment. Please try again.",
          type: AppSnackType.error,
        );
      }
    }
  }

  /// Top-level comment that owns [CommentsSheet.highlightCommentId] — itself,
  /// or the parent when the target is a reply. First time it's found, schedules
  /// the one-shot expand + scroll + blue flash.
  String? _resolveHighlightBlock(List<Map<String, dynamic>> comments) {
    final target = widget.highlightCommentId;
    if (target == null) return null;
    String? blockId;
    var isReply = false;
    for (final c in comments) {
      if (c['id'] == target) {
        blockId = c['id'] as String;
        break;
      }
      final replies = (c['replies'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      if (replies.any((r) => r['id'] == target)) {
        blockId = c['id'] as String;
        isReply = true;
        break;
      }
    }
    if (blockId == null || _highlightConsumed) return blockId;
    _highlightConsumed = true;
    if (isReply) _expandedReplies.add(blockId);
    _highlightFlash = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The thread is a LAZY ListView.builder, so the target's element exists
      // only once it has been built. A comment below the first viewport has no
      // currentContext on this frame, and ensureVisible would silently no-op —
      // the notification would open the sheet at the top instead of at the
      // comment it points to.
      //
      // _scrollToHighlight walks the list toward the target instead: each jump
      // builds the next screenful, so the key materialises and ensureVisible
      // can finish the job precisely. Bounded so a target that never resolves
      // (deleted mid-flight, filtered out) stops rather than looping.
      _scrollToHighlight();
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _highlightFlash = false);
      });
    });
    return blockId;
  }

  /// Brings the deep-linked comment into view in the lazy thread.
  ///
  /// Fast path: it is already built (short thread, or the target is near the
  /// top) — ensureVisible immediately, which is what the eager list always did.
  ///
  /// Otherwise page down [_highlightScrollStep] at a time, giving the builder a
  /// frame to materialise the next run of items, and re-check. Stops on the
  /// first frame the key resolves, at the end of the list, or after
  /// [_highlightScrollMaxSteps] — never spins.
  Future<void> _scrollToHighlight([int step = 0]) async {
    if (!mounted) return;

    final ctx = _highlightBlockKey.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
      return;
    }

    if (step >= _highlightScrollMaxSteps) return;

    // No context yet: the target is below what has been built. Nudge down and
    // let the next frame build more. Scrollable.of() is read from the sheet's
    // own context, which sits above the ListView.
    final scrollable = Scrollable.maybeOf(context);
    final position = scrollable?.position;
    if (position == null || !position.hasContentDimensions) return;
    if (position.pixels >= position.maxScrollExtent) return;

    final next = (position.pixels + _highlightScrollStep)
        .clamp(0.0, position.maxScrollExtent);
    await position.animateTo(
      next,
      duration: const Duration(milliseconds: 120),
      curve: Curves.linear,
    );
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    await _scrollToHighlight(step + 1);
  }

  /// One screenful-ish per hop while hunting the deep-link target.
  static const double _highlightScrollStep = 600;

  /// Ceiling on those hops. 40 x 600px is ~24,000px of thread — far past any
  /// realistic comment count, so this only ever fires when the target cannot be
  /// found at all, and then it stops instead of scrolling forever.
  static const int _highlightScrollMaxSteps = 40;

  @override
  Widget build(BuildContext context) {
    const width = kThreadMetrics;
    final comments = _getComments();
    final highlightBlockId = _resolveHighlightBlock(comments);

    // Centred dialog on wide screens: the Dialog already supplies the height,
    // so the corners round all the way and the body just fills it.
    if (widget.asDialog) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: _sheetBody(width, comments, highlightBlockId),
      );
    }

    // Phone / narrow: the admin panel's sheet — a fixed 92% of the viewport
    // with a drag handle, NOT a DraggableScrollableSheet. Admin's height is not
    // draggable, so neither is this; a thread that resizes under the thumb on
    // two surfaces and not the third is exactly the inconsistency being fixed.
    return Padding(
      // No Scaffold here to resize for us, so the sheet yields to the keyboard
      // itself — and it must happen OUTSIDE the FractionallySizedBox, or 92%
      // is taken of the full screen and the composer ends up behind the keys.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _sheetBody(width, comments, highlightBlockId),
        ),
      ),
    );
  }

  /// The sheet's contents. Three layouts share one set of parts:
  ///
  ///  - bottom sheet — drag handle, "Comments", thread, composer;
  ///  - stacked dialog — post recap riding on top of the thread;
  ///  - split dialog — recap in its own left column beside the thread, for
  ///    viewports that are wide but short. See [commentsUseSplitLayout].
  Widget _sheetBody(
    double width,
    List<Map<String, dynamic>> comments,
    String? highlightBlockId,
  ) {
    final split =
        widget.asDialog && commentsUseSplitLayout(MediaQuery.of(context).size);

    if (split) {
      return Column(
        children: [
          _header(width),
          Container(height: 1, color: CitizenUi.sharedBorder),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The post gets its own scroll so a long body or a tall photo
                // never pushes the thread out of reach — the whole point of
                // splitting rather than stacking on a short viewport.
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      width * 0.035,
                      width * 0.03,
                      width * 0.035,
                      width * 0.03,
                    ),
                    child: CommentPostRecap(post: _livePost(), width: width),
                  ),
                ),
                Container(width: 1, color: CitizenUi.sharedBorder),
                // Thread keeps the composer pinned beneath it, so replying
                // never means scrolling back past the post.
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      Expanded(
                        child: _thread(width, comments, highlightBlockId),
                      ),
                      _buildCommentInput(width),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (!widget.asDialog) dragHandle(width),
        _header(width),
        Container(height: 1, color: CitizenUi.sharedBorder),
        Expanded(
          child: _thread(
            width,
            comments,
            highlightBlockId,
            // Stacked dialog only: the recap rides at the top of the thread's
            // own scroll. The split layout has already placed it in its own
            // column, and the bottom sheet deliberately opens straight into
            // the thread — there the feed is still visible behind the sheet,
            // and a recap is what pushed the comments off a phone screen.
            leading: widget.asDialog
                ? CommentPostRecap(post: _livePost(), width: width)
                : null,
          ),
        ),
        _buildCommentInput(width),
      ],
    );
  }

  Widget _header(double width) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        width * 0.045,
        widget.asDialog ? width * 0.035 : width * 0.015,
        width * 0.025,
        width * 0.035,
      ),
      child: Row(
        children: [
          // Dialog: the post's own title, centred, so a modal covering the
          // feed still says which post you are reading. Bottom sheet: the
          // plain left-aligned label, since the post is right behind it.
          //
          // No count either way: it drifts against optimistic comments
          // mid-send, and the thread below already shows how many there are.
          if (widget.asDialog)
            Expanded(
              child: Padding(
                // Balances the close button so the title lands optically
                // centred rather than centred-then-shoved-left.
                padding: EdgeInsets.only(left: width * 0.06),
                child: Text(
                  "${widget.post['author'] ?? 'This'}'s Post",
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: width * 0.0425,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1F2937),
                  ),
                ),
              ),
            )
          else ...[
            Text(
              'Comments',
              style: TextStyle(
                fontSize: width * 0.0425,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1F2937),
              ),
            ),
            const Spacer(),
          ],
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: width * 0.06,
              color: const Color(0xFF6B7280),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// The comment list. [leading] is prepended inside the scroll view — used by
  /// the stacked dialog to float the post recap above the thread.
  Widget _thread(
    double width,
    List<Map<String, dynamic>> comments,
    String? highlightBlockId, {
    Widget? leading,
  }) {
    // LAZY. This was `ListView(children: [...])`, the non-builder constructor —
    // it LOOKS lazy but eagerly builds every child before the sheet paints. Each
    // child is a full comment item WITH its replies, so opening a post with 300
    // comments built 300 subtrees up front, on a bottom sheet that shows maybe
    // six. `.builder` builds only what is visible plus a small cache extent.
    //
    // Index layout, kept identical to the old `children:` order:
    //   0                      -> `leading`, when one was passed (the stacked
    //                             dialog's post recap). Absent otherwise, so
    //                             every later index shifts by `lead`.
    //   lead .. lead+n-1       -> the comments
    //   lead+n                 -> the trailing spacer
    final int lead = leading == null ? 0 : 1;
    final int n = comments.length;

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        width * 0.035,
        width * 0.03,
        width * 0.035,
        width * 0.03,
      ),
      itemCount: lead + n + 1,
      itemBuilder: (_, index) {
        if (lead == 1 && index == 0) return leading;
        if (index == lead + n) return SizedBox(height: width * 0.04);

        final c = comments[index - lead];
        final item = buildCommentItem(
          context,
          width,
          c,
          likedComments: widget.likedComments,
          onToggleLike: (id) {
            widget.onToggleLike(id);
            setState(() {});
          },
          onReply: () => _setReplyByCommentId(
            c['id'] as String,
            c['author'] as String? ?? '',
          ),
          showReplies: true,
          expandedReplies: _expandedReplies,
          onToggleExpandReplies: _toggleExpandReplies,
          onReplyToReply: (authorName, commentId) =>
              _setReplyByCommentId(commentId, authorName),
          currentUserId: _currentUserId,
          onEdit: _handleEditComment,
          onDelete: _handleDeleteComment,
          official: true,
        );
        if (highlightBlockId != c['id']) return item;
        // Deep-link target: blue wash that melts away once seen. The key must
        // stay on this element — _highlightBlockKey is what the deep-link scroll
        // measures against to bring the target comment into view.
        return AnimatedContainer(
          key: _highlightBlockKey,
          duration: const Duration(milliseconds: 450),
          decoration: BoxDecoration(
            color: _highlightFlash
                ? AppColors.primaryBlue.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: item,
        );
      },
    );
  }

  Widget _buildCommentInput(double width) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: CitizenUi.sharedBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null)
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  width * 0.05,
                  width * 0.025,
                  width * 0.03,
                  width * 0.025,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFEFF6FF),
                  border: Border(
                    bottom: BorderSide(color: CitizenUi.sharedBorder),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.reply_rounded,
                      size: width * 0.040,
                      color: AppColors.primaryBlue,
                    ),
                    SizedBox(width: width * 0.015),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Replying to ',
                              style: TextStyle(
                                fontSize: width * 0.032,
                                color: const Color(0xFF6B7280),
                              ),
                            ),
                            TextSpan(
                              text: _replyingTo,
                              style: TextStyle(
                                fontSize: width * 0.032,
                                fontWeight: FontWeight.w800,
                                color: _replyingTo == 'yourself'
                                    ? const Color(0xFF6B7280)
                                    : AppColors.primaryBlue,
                                fontStyle: _replyingTo == 'yourself'
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelReply,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.all(width * 0.015),
                        child: Icon(
                          Icons.close_rounded,
                          size: width * 0.045,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                width * 0.03,
                width * 0.02,
                width * 0.03,
                width * 0.025,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: width * 0.085,
                    height: width * 0.085,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE5E7EB),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (_myPhotoUrl != null && _myPhotoUrl!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: _myPhotoUrl!,
                            cacheKey: _myPhotoPath ?? _myPhotoUrl!,
                            memCacheWidth: 110,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 150),
                            placeholder: (context, url) => const Icon(
                              Icons.person_rounded,
                              color: Color(0xFF9CA3AF),
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.person_rounded,
                              color: Color(0xFF9CA3AF),
                            ),
                          )
                        : const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF9CA3AF),
                          ),
                  ),
                  SizedBox(width: width * 0.03),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: width * 0.35),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: width * 0.04,
                          vertical: width * 0.022,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(width * 0.06),
                          border: Border.all(
                            color: _inputFocus.hasFocus
                                ? AppColors.primaryBlue.withValues(alpha: 0.4)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocus,
                          maxLines: null,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                          // Enter sends (hardware Enter on web/desktop, Send
                          // key on phone keyboards); Shift+Enter still inserts
                          // a newline for multi-line comments.
                          textInputAction: TextInputAction.send,
                          textCapitalization: TextCapitalization.sentences,
                          enabled: !_sending,
                          decoration: InputDecoration(
                            hintText: _replyingTo != null
                                ? 'Write a reply...'
                                : widget.officialName != null
                                ? 'Write a comment as ${widget.officialName}…'
                                : 'Write a comment...',
                            hintStyle: TextStyle(
                              fontSize: width * 0.035,
                              color: const Color(0xFF9CA3AF),
                            ),
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          style: TextStyle(
                            fontSize: width * 0.035,
                            color: const Color(0xFF1F2937),
                            height: 1.4,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: width * 0.025),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _sending ? null : _send,
                    child: _sending
                        ? SizedBox(
                            width: width * 0.058,
                            height: width * 0.058,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        // The admin panel's filled blue disc.
                        : Container(
                            padding: EdgeInsets.all(width * 0.0275),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryBlue,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: width * 0.045,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
