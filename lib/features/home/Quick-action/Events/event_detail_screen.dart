import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/widgets/responsive_page.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/event_status_pill.dart';
import 'events_screen.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/theme/mobile_metrics.dart';
import '../../../../core/widgets/app_back_chevron.dart';

class EventDetailScreen extends StatefulWidget {
  final EventItem event;
  final String username;

  const EventDetailScreen({
    super.key,
    required this.event,
    required this.username,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  late final Animation<Offset> _slideAnim;

  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _shareEvent() async {
    if (_isSharing) return; // guard against double-tap
    HapticFeedback.lightImpact();
    setState(() => _isSharing = true);

    // iPad needs an anchor rectangle for the share popover, or it throws.
    // Ignored on iPhone/Android. We anchor to this screen's render box.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    final e = widget.event;
    final text =
        '${e.title}\n'
        '📅 ${e.date}  •  ⏰ ${e.time}\n'
        '📍 ${e.location}'
        '${e.description != null && e.description!.isNotEmpty ? '\n\n${e.description}' : ''}';

    try {
      if (e.imageUrl == null || e.imageUrl!.isEmpty) {
        await Share.share(text, subject: e.title, sharePositionOrigin: origin);
      } else {
        final res = await http.get(Uri.parse(e.imageUrl!));
        if (res.statusCode == 200) {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/event_${e.title.hashCode}.jpg');
          await file.writeAsBytes(res.bodyBytes);
          await Share.shareXFiles(
            [XFile(file.path)],
            text: text,
            subject: e.title,
            sharePositionOrigin: origin,
          );
        } else {
          // Download failed → still share the text.
          await Share.share(
            text,
            subject: e.title,
            sharePositionOrigin: origin,
          );
        }
      }
    } catch (_) {
      // Network/file error → fall back to text-only share.
      await Share.share(text, subject: e.title, sharePositionOrigin: origin);
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = uiScaleWidth(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: ResponsivePageBody(
        maxWidth: 760,
        shellTitle: 'Event Details',
        shellSubtitle: 'View the full details of this community event.',
        shellIcon: Icons.event_rounded,
        shellContentWidth: 640,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(w),
              Expanded(
                child: SlideTransition(
                  position: _slideAnim,
                  child: _buildBody(w),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(double w) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: w * 0.04, vertical: w * 0.03),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: w * 0.09,
              height: w * 0.09,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(w * 0.025),
                border: Border.all(color: kBackChevronBorder, width: 1),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: w * 0.046,
                color: kBackChevronGlyph,
              ),
            ),
          ),
          SizedBox(width: w * 0.03),
          Image.asset(
            'assets/images/newslogo.webp',
            height: w * 0.085,
            fit: BoxFit.contain,
            errorBuilder: (context, url, error) => Row(
              children: [
                Icon(
                  Icons.account_balance_rounded,
                  size: w * 0.07,
                  color: AppColors.primaryBlue,
                ),
                SizedBox(width: w * 0.02),
                Text(
                  'GovPulse',
                  style: TextStyle(
                    fontSize: w * 0.048,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody(double w) {
    final event = widget.event;
    final imageW = w * 0.38;
    final imageH = imageW * 1.1;

    final List<String> whatToExpect =
        event.whatToExpect
            ?.split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    final List<String> requirements =
        event.requirements
            ?.split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            // Always fill at least the visible height so the Spacer below
            // can push the Share button to the bottom on short content.
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top card: category badge + title + image + meta ──────
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      w * 0.04,
                      w * 0.02,
                      w * 0.04,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // row: left text + right image
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // LEFT — badge + title + description
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // category badge + time-status pill
                                  Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: w * 0.028,
                                          vertical: w * 0.010,
                                        ),
                                        decoration: BoxDecoration(
                                          color: event.categoryColor,
                                          borderRadius: BorderRadius.circular(
                                            w * 0.015,
                                          ),
                                        ),
                                        child: Text(
                                          event.category,
                                          style: TextStyle(
                                            fontSize: w * 0.028,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      EventStatusPill(
                                        eventDate: event.eventDate,
                                        eventTime: event.time,
                                        fontSize: w * 0.028,
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: w * 0.025),
                                  // title
                                  Text(
                                    event.title,
                                    style: TextStyle(
                                      fontSize: w * 0.052,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF1F2937),
                                      height: 1.2,
                                    ),
                                  ),
                                  SizedBox(height: w * 0.018),
                                  // short description under title
                                  if (event.description != null &&
                                      event.description!.isNotEmpty)
                                    Text(
                                      event.description!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: w * 0.032,
                                        color: const Color(0xFF6B7280),
                                        height: 1.5,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(width: w * 0.04),
                            // RIGHT — image
                            ClipRRect(
                              borderRadius: BorderRadius.circular(w * 0.025),
                              child: SizedBox(
                                width: imageW,
                                height: imageH,
                                child: event.imageUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: event.imageUrl!,
                                        fit: BoxFit.cover,
                                        fadeInDuration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        fadeOutDuration: const Duration(
                                          milliseconds: 100,
                                        ),
                                        placeholder: (context, url) =>
                                            const _ShimmerBox(),
                                        errorWidget: (context, url, error) =>
                                            _imagePlaceholder(imageW),
                                      )
                                    : _imagePlaceholder(imageW),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: w * 0.04),
                        Divider(color: CitizenUi.sharedBorder, height: 1),
                        SizedBox(height: w * 0.04),

                        // ── Location ──────────────────────────────────────
                        _metaRow(
                          icon: Icons.location_on_rounded,
                          iconColor: AppColors.primaryBlue,
                          label: event.location,
                          sublabel: _locationSublabel(event.location),
                          w: w,
                        ),
                        SizedBox(height: w * 0.03),

                        // ── Date ──────────────────────────────────────────
                        _metaRow(
                          icon: Icons.calendar_month_rounded,
                          iconColor: AppColors.primaryBlue,
                          label: event.date,
                          sublabel: _dayLabel(event.eventDate),
                          w: w,
                        ),
                        SizedBox(height: w * 0.03),

                        // ── Time ──────────────────────────────────────────
                        _metaRow(
                          icon: Icons.access_time_rounded,
                          iconColor: AppColors.primaryBlue,
                          label: event.time,
                          sublabel: _durationLabel(event.time),
                          w: w,
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: w * 0.06),

                  // ── About This Event ───────────────────────────────────
                  if (event.description != null &&
                      event.description!.isNotEmpty) ...[
                    _sectionBlock(
                      title: 'About This Event',
                      w: w,
                      child: Text(
                        event.description!,
                        style: TextStyle(
                          fontSize: w * 0.036,
                          color: const Color(0xFF374151),
                          height: 1.6,
                        ),
                      ),
                    ),
                    SizedBox(height: w * 0.04),
                  ],

                  // ── What to Expect ─────────────────────────────────────
                  if (whatToExpect.isNotEmpty) ...[
                    _sectionBlock(
                      title: 'What to Expect',
                      w: w,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: whatToExpect
                            .map((item) => _bulletItem(item, w))
                            .toList(),
                      ),
                    ),
                    SizedBox(height: w * 0.04),
                  ],

                  // ── Requirements ───────────────────────────────────────
                  if (requirements.isNotEmpty) ...[
                    _sectionBlock(
                      title: 'Requirements',
                      w: w,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: requirements
                            .map((item) => _bulletItem(item, w))
                            .toList(),
                      ),
                    ),
                    SizedBox(height: w * 0.04),
                  ],

                  // Pushes the Share button to the bottom when content is
                  // short; collapses to zero when content overflows.
                  const Spacer(),

                  SizedBox(height: w * 0.02),

                  // ── Share Event button ─────────────────────────────────
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: w * 0.04),
                    child: OutlinedButton(
                      onPressed: _isSharing ? null : _shareEvent,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: CitizenUi.sharedBorder,
                          width: 1.5,
                        ),
                        backgroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white,
                        minimumSize: Size(double.infinity, w * 0.135),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(w * 0.032),
                        ),
                      ),
                      child: _isSharing
                          ? SizedBox(
                              width: w * 0.05,
                              height: w * 0.05,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF374151),
                                ),
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.share_rounded,
                                  size: w * 0.046,
                                  color: const Color(0xFF374151),
                                ),
                                SizedBox(width: w * 0.02),
                                Text(
                                  'Share Event',
                                  style: TextStyle(
                                    fontSize: w * 0.038,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF374151),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  SizedBox(height: w * 0.06),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Reusable widgets ──────────────────────────────────────────────────────

  Widget _imagePlaceholder(double size) => Container(
    color: const Color(0xFFE5E7EB),
    child: Center(
      child: Icon(
        Icons.image_rounded,
        size: size * 0.35,
        color: const Color(0xFF9CA3AF),
      ),
    ),
  );

  Widget _metaRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String? sublabel,
    required double w,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: w * 0.05, color: iconColor),
        SizedBox(width: w * 0.03),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1F2937),
              ),
            ),
            if (sublabel != null && sublabel.isNotEmpty) ...[
              SizedBox(height: w * 0.004),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: w * 0.030,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _sectionBlock({
    required String title,
    required double w,
    required Widget child,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: w * 0.042,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1F2937),
            ),
          ),
          SizedBox(height: w * 0.022),
          child,
        ],
      ),
    );
  }

  Widget _bulletItem(String text, double w) {
    // Check if any word in text should be bold (wrapped in **)
    return Padding(
      padding: EdgeInsets.only(bottom: w * 0.016),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: w * 0.01),
            child: const Text('• ', style: TextStyle(color: Color(0xFF374151))),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: w * 0.034,
                color: const Color(0xFF374151),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Date / location helpers ───────────────────────────────────────────────

  String _dayLabel(DateTime d) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[d.weekday - 1];
  }

  String _locationSublabel(String location) {
    // e.g. "RHU – Aparri" → sublabel is the city if comma present
    if (location.contains(',')) {
      return location.split(',').skip(1).join(',').trim();
    }
    return '';
  }

  String _durationLabel(String timeRange) {
    try {
      final parts = timeRange.split(RegExp(r'[-–]'));
      if (parts.length < 2) return '';
      DateTime parse(String s) {
        s = s.trim();
        final isPm = s.toUpperCase().contains('PM');
        final isAm = s.toUpperCase().contains('AM');
        s = s.replaceAll(RegExp(r'[APM\s]', caseSensitive: false), '');
        final hm = s.split(':');
        int h = int.parse(hm[0]);
        final m = hm.length > 1 ? int.parse(hm[1]) : 0;
        if (isPm && h != 12) h += 12;
        if (isAm && h == 12) h = 0;
        return DateTime(2000, 1, 1, h, m);
      }

      final start = parse(parts[0]);
      final end = parse(parts[1]);
      final diff = end.difference(start);
      final hrs = diff.inHours;
      final mins = diff.inMinutes % 60;
      if (mins == 0) return '$hrs ${hrs == 1 ? "hour" : "hours"}';
      return '$hrs h $mins min';
    } catch (_) {
      return '';
    }
  }
}

// ── Shimmer placeholder ───────────────────────────────────────────────────
// Self-contained animated shimmer used while the event image loads.
// Dependency-free: a gradient swept across a grey box.
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox();

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (context, child) {
        // Slide the gradient from off-screen left to off-screen right.
        final t = _shimmerCtrl.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 - 2.0 * (1 - t), 0),
              end: Alignment(1.0 - 2.0 * (1 - t), 0),
              colors: const [
                Color(0xFFE5E7EB),
                Color(0xFFF3F4F6),
                Color(0xFFE5E7EB),
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: Container(color: const Color(0xFFE5E7EB)),
        );
      },
    );
  }
}
