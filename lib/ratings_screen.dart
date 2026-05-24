// ratings_screen.dart
//
import 'dart:async';
import 'package:flutter/material.dart';
import 'comments_screen.dart';
import 'goodfor_screen.dart';
import 'preview_screen.dart';
import 'services/session_cache.dart';
import 'sub_preview_screen/review_formatter.dart' as formatter;
import 'sub_preview_screen/review_context.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'services/draft_cache.dart';

class RatingsScreen extends StatefulWidget {
  final ReviewContext context;

  const RatingsScreen({super.key, required this.context});

  @override
  State<RatingsScreen> createState() => _RatingsScreenState();
}

class _RatingsScreenState extends State<RatingsScreen> {
  late int foodRating;
  late int serviceRating;
  late int ambianceRating;
  late int drinksRating;
  late int vfmsRating;
  late int michelinStars;
  late TextEditingController _costController;

  late double foodRatingDisplay;
  late double serviceRatingDisplay;
  late double ambianceRatingDisplay;
  late double drinksRatingDisplay;
  late double vfmsRatingDisplay;

  @override
  void initState() {
    super.initState();
    final reviewMap = widget.context.reviewMap;

    foodRating = reviewMap['foodRating'] ?? 0;
    serviceRating = reviewMap['serviceRating'] ?? 0;
    ambianceRating = reviewMap['ambianceRating'] ?? 0;
    drinksRating = reviewMap['drinksRating'] ?? 0;
    vfmsRating = reviewMap['vfmsRating'] ?? 0;
    michelinStars = reviewMap['michelinStars'] ?? 0;

    final costValue = reviewMap['cost'];
    _costController = TextEditingController(
      text: (costValue == null || costValue == '0') ? '' : costValue.toString(),
    );
    _costController.addListener(() => widget.context.hasChanges = true);

    foodRatingDisplay = (foodRating / 4).clamp(0.0, 5.0);
    serviceRatingDisplay = (serviceRating / 4).clamp(0.0, 5.0);
    ambianceRatingDisplay = (ambianceRating / 4).clamp(0.0, 5.0);
    drinksRatingDisplay = (drinksRating / 4).clamp(0.0, 5.0);
    vfmsRatingDisplay = (vfmsRating / 4).clamp(0.0, 5.0);
  }

@override
  void dispose() {
    _costController.dispose();
    super.dispose();
  }

  void _clearRatings() {
    if (!mounted) return;
    setState(() {
      foodRating = 0;
      serviceRating = 0;
      ambianceRating = 0;
      drinksRating = 0;
      vfmsRating = 0;
      michelinStars = 0;

      foodRatingDisplay = 0;
      serviceRatingDisplay = 0;
      ambianceRatingDisplay = 0;
      drinksRatingDisplay = 0;
      vfmsRatingDisplay = 0;
      _costController.clear();
    });
  }

  void _saveToContext() {
    final reviewMap = widget.context.reviewMap;

    reviewMap['foodRating'] = foodRating;
    reviewMap['serviceRating'] = serviceRating;
    reviewMap['ambianceRating'] = ambianceRating;
    reviewMap['drinksRating'] = drinksRating;
    reviewMap['vfmsRating'] = vfmsRating;
    reviewMap['michelinStars'] = michelinStars;

    final String costText = _costController.text.trim();
    reviewMap['cost'] = costText.isEmpty ? '' : costText;
    reviewMap['currency'] = SessionCache.currency;

    final totalRating =
        foodRating + serviceRating + ambianceRating + drinksRating + vfmsRating;
    reviewMap['restrating'] = totalRating;
  }

  void _goToNextScreen() {
    _saveToContext();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GoodForScreen(context: widget.context)),
    );
  }

  void _goToPreviewScreen() {
    _saveToContext(); // Ensure ratings are saved

    final email = SessionCache.userEmail;
    final name = SessionCache.userName;

    final formatted = formatter.formatReviewData(
      widget.context.reviewMap,
      email,
      name,
    );

    // Persist draft so a crash before auto-save cannot lose data
    unawaited(DraftCache.save(widget.context.reviewKey, formatted));

    final previewContext = ReviewContext(
      reviewMap: formatted,
      isEditing: widget.context.isEditing,
      reviewKey: widget.context.reviewKey,
      hasChanges: widget.context.hasChanges,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(context: previewContext, mode: 'preview'),
      ),
    );
  }

  void _goBack() {
    _saveToContext();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => CommentsScreen(context: widget.context)),
    );
  }

  Widget _buildStarRatingRow(
    String label,
    double displayValue,
    void Function(double) updateDisplay,
    void Function(int) updateStored,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: AppFonts.standard.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          RatingBar.builder(
            initialRating: displayValue,
            minRating: 0,
            allowHalfRating: true,
            itemCount: 5,
            itemSize: 30,
            itemPadding: const EdgeInsets.symmetric(horizontal: 2),
            itemBuilder: (context, _) =>
                const Icon(Icons.star, color: AppColors.blue),
            onRatingUpdate: (val) {
              if (!mounted) return;
              setState(() {
                updateDisplay(val);
                updateStored((val * 4).round());
                widget.context.hasChanges = true;
              });
            },
          ),
          const SizedBox(width: 12),
          Text(
            '${(displayValue * 4).round()}',
            style: AppFonts.bold.copyWith(fontSize: 18, color: AppColors.black),
          ),
        ],
      ),
    );
  }

  Widget _michelinSelector() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(4, (index) {
            final selected = michelinStars == index;
            return InkWell(
              onTap: () {
                if (!mounted) return;
                setState(() {
                  michelinStars = index;
                  widget.context.hasChanges = true;
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.black26),
                      color: selected
                          ? AppColors.darkGreen
                          : AppColors.transparent,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.radio_button_checked,
                        size: 14,
                        color: selected ? AppColors.white : AppColors.black38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$index',
                    style: AppFonts.standard.copyWith(fontSize: 16),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalRating =
        foodRating + serviceRating + ambianceRating + drinksRating + vfmsRating;

    // Shared button style for consistent label sizes across the action buttons
    final ButtonStyle actionBtnBase = ElevatedButton.styleFrom(
      textStyle: AppFonts.bold.copyWith(fontSize: 14, letterSpacing: 0.4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      minimumSize: const Size(0, 44),
    );

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          AppStr.rateTitle,
          style: AppFonts.bold.copyWith(color: AppColors.white),
        ),
        backgroundColor: AppColors.darkGreen,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  Center(
                    child: Text(
                      AppStr.rateSubtitle,
                      style: AppFonts.bold.copyWith(fontSize: 18),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildStarRatingRow(
                    AppStr.foodLabel,
                    foodRatingDisplay,
                    (val) => foodRatingDisplay = val,
                    (val) => foodRating = val,
                  ),
                  const SizedBox(height: 8),
                  _buildStarRatingRow(
                    AppStr.serviceLabel,
                    serviceRatingDisplay,
                    (val) => serviceRatingDisplay = val,
                    (val) => serviceRating = val,
                  ),
                  const SizedBox(height: 8),
                  _buildStarRatingRow(
                    AppStr.ambianceLabel,
                    ambianceRatingDisplay,
                    (val) => ambianceRatingDisplay = val,
                    (val) => ambianceRating = val,
                  ),
                  const SizedBox(height: 8),
                  _buildStarRatingRow(
                    AppStr.drinksLabel,
                    drinksRatingDisplay,
                    (val) => drinksRatingDisplay = val,
                    (val) => drinksRating = val,
                  ),
                  const SizedBox(height: 8),
                  _buildStarRatingRow(
                    AppStr.vfmsLabel,
                    vfmsRatingDisplay,
                    (val) => vfmsRatingDisplay = val,
                    (val) => vfmsRating = val,
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 1),
                    child: Text(
                      AppStr.vfmText,
                      style: AppFonts.standard.copyWith(
                        fontSize: 16,
                        color: AppColors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(AppStr.costLabel, style: AppFonts.standard.copyWith(fontSize: 18, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 12),
                      Text(SessionCache.currency, style: AppFonts.standard.copyWith(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _costController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: AppStr.amountLabel,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(
                            AppStr.michelinLabel,
                            style: AppFonts.bold.copyWith(fontSize: 18),
                          ),
                        ),
                        Expanded(child: _michelinSelector()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      '${AppStr.totalRatingLabel} $totalRating / 100',
                      style: AppFonts.bold.copyWith(
                        fontSize: 20,
                        color: const Color(0xFFB00020),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
          const SizedBox(height: 36),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: _goBack,
                        style: actionBtnBase.copyWith(
                          backgroundColor: WidgetStateProperty.all(
                            AppColors.ochre,
                          ),
                          foregroundColor: WidgetStateProperty.all(
                            AppColors.black,
                          ),
                        ),
                        child: Text(
                          AppStr.back,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: _clearRatings,
                        style: actionBtnBase.copyWith(
                          backgroundColor: WidgetStateProperty.all(
                            AppColors.btnClear,
                          ),
                          foregroundColor: WidgetStateProperty.all(
                            AppColors.btnText,
                          ),
                        ),
                        child: Text(
                          AppStr.clear,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: _goToPreviewScreen,
                        style: actionBtnBase.copyWith(
                          backgroundColor: WidgetStateProperty.all(
                            AppColors.btnPreview,
                          ),
                          foregroundColor: WidgetStateProperty.all(
                            AppColors.btnText,
                          ),
                        ),
                        child: Text(
                          AppStr.preview,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ElevatedButton(
                        onPressed: _goToNextScreen,
                        style: actionBtnBase.copyWith(
                          backgroundColor: WidgetStateProperty.all(
                            AppColors.yellow,
                          ),
                          foregroundColor: WidgetStateProperty.all(
                            AppColors.black,
                          ),
                        ),
                        child: Text(
                          AppStr.next,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
