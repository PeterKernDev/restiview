// top_screen.dart
// Main dashboard screen after user login. Provides access to review creation, viewing, settings, help, sign-out, and friends access.
// Updated: friends button is disabled (greyed out) when the current user does not accept friend requests
// (determined by users/$uid/userSettings7 or default true).
//
// Change: removed accepted-friends counter entirely (no reads or display).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'general_screen.dart';
import 'test_general_screen.dart';
import 'settings_screen.dart';
import 'list_screen.dart';
import 'sub_preview_screen/review_context.dart';
import 'services/session_cache.dart';
import 'services/db_utils.dart';
import 'services/review_info_builder.dart';
import 'services/mailbox_helper.dart';
import 'constants/strings.dart';
import 'constants/colors.dart';
import 'constants/fonts.dart';
import 'constants/restiview_constants.dart';
import 'services/draft_cache.dart';
import 'preview_screen.dart';

class TopScreen extends StatefulWidget {
  const TopScreen({super.key});

  @override
  State<TopScreen> createState() => _TopScreenState();
}

class _TopScreenState extends State<TopScreen> {
  bool _isLoading = false;
  bool _isSigningOut = false;
  bool _acceptsFriends =
      true; // whether this user accepts friends (controls button enabled)
  bool _hasRequestedReviews = false; // whether user has any requested reviews
  bool _hasFriends = false; // whether user has any friends
  bool _hasPendingMailboxRequests =
      false; // whether user has pending friend/review requests
  bool _hasNewReviewsDelivered =
      false; // whether user has new reviews delivered from friends
  Timer? _mailboxCheckTimer; // Periodic timer to check mailbox

  @override
  void initState() {
    super.initState();
    _loadAcceptsFriends();
    _checkRequestedReviews();
    _checkFriends();
    _checkNewReviewsDelivered(); // Check for new reviews delivered
    _checkMailbox(); // Check mailbox on screen open
    _startMailboxTimer(); // Start periodic mailbox checks
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForDraft());
  }

  @override
  void dispose() {
    _mailboxCheckTimer?.cancel();
    super.dispose();
  }

  // Check for a locally persisted draft and offer to resume editing.
  Future<void> _checkForDraft() async {
    if (!mounted) return;
    final draft = await DraftCache.load();
    if (draft == null) return;
    if (!mounted) return;

    final reviewMap = draft['reviewMap'];
    final reviewKey = draft['reviewKey'] as String?;
    if (reviewMap is! Map) {
      await DraftCache.clear();
      return;
    }

    final String restName =
        (reviewMap['restname'] ?? reviewMap['restaurantName'] ?? '')
            .toString()
            .trim();
    final String message = AppStr.draftResumeMessage.replaceFirst(
      '%s',
      restName.isNotEmpty ? restName : 'unknown restaurant',
    );

    final bool? resume = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(AppStr.draftResumeTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStr.draftDiscard),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStr.draftResume),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (resume != true) {
      await DraftCache.clear();
      return;
    }

    // Restore the draft into a ReviewContext and navigate to PreviewScreen.
    // hasChanges: true causes auto-save to fire on arrival for existing reviews.
    final restoredMap = Map<String, dynamic>.from(reviewMap);
    final ctx = ReviewContext(
      reviewMap: restoredMap,
      isEditing: true,
      reviewKey: reviewKey,
      hasChanges: reviewKey != null, // trigger auto-save for existing reviews
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(context: ctx, mode: 'preview'),
      ),
    );
  }

  void _checkFriends() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final friendsRef = FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(user.uid)
        .child('friends');
    final snapshot = await friendsRef.get();
    if (mounted) {
      setState(() {
        _hasFriends = snapshot.exists && (snapshot.value != null);
      });
    }
  }

  void _startMailboxTimer() {
    // Start periodic timer to check mailbox every N seconds
    // mailboxCheckIntervalSeconds is 30 for testing, 600 for production
    _mailboxCheckTimer = Timer.periodic(
      Duration(seconds: mailboxCheckIntervalSeconds),
      (Timer timer) {
        _checkMailbox();
      },
    );
  }

  Future<void> _checkMailbox() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      return;
    }

    final String normalizedEmail = normalizeEmailForPath(
      user.email!.toLowerCase(),
    );

    try {
      // Process any pending mailbox requests
      bool hasPending = await hasMailboxRequests(normalizedEmail);
      if (hasPending) {
        await processUserMailbox(user.uid, normalizedEmail);
      }

      // After processing mailbox, check if there are any pending friend actions
      // (unaccepted friend requests or review requests)
      bool hasPendingActions = await _hasPendingFriendActions(user.uid);

      // Also check for new reviews delivered
      bool hasNewReviews = await _checkIfUserHasNewReviewsDelivered(user.uid);

      if (mounted) {
        setState(() {
          _hasPendingMailboxRequests = hasPendingActions;
          _hasNewReviewsDelivered = hasNewReviews;
        });
      }
    } catch (e) {
      // Silent failure with logging
      appLog('Error checking mailbox: $e');
    }
  }

  /// Check if user has any pending friend actions requiring attention
  /// Returns true if there are friend requests (statusCode=2) or review requests (statusCode=3)
  Future<bool> _hasPendingFriendActions(String uid) async {
    try {
      final DatabaseReference friendsRef = FirebaseDatabase.instance.ref(
        'users/$uid/friends',
      );
      final DataSnapshot snapshot = await friendsRef.get();

      if (!snapshot.exists || snapshot.value == null) {
        return false;
      }

      if (snapshot.value is! Map) {
        return false;
      }

      final Map<dynamic, dynamic> friends = snapshot.value as Map;

      // Check if any friend has statusCode 2 (FR-WANTED) or 3 (RV-WANTED)
      for (final entry in friends.values) {
        if (entry is Map) {
          final statusCode = entry['statusCode'];
          if (statusCode == 2 || statusCode == 3) {
            return true; // Found a pending action
          }
        }
      }

      return false;
    } catch (e) {
      appLog('Error checking pending friend actions: $e');
      return false;
    }
  }

  /// Check if user has any new reviews delivered from friends
  /// Returns true if any friend has hasNewReviews flag set
  Future<bool> _checkIfUserHasNewReviewsDelivered(String uid) async {
    try {
      final DatabaseReference friendsRef = FirebaseDatabase.instance.ref(
        'users/$uid/friends',
      );
      final DataSnapshot snapshot = await friendsRef.get();

      if (!snapshot.exists || snapshot.value == null) {
        return false;
      }

      if (snapshot.value is! Map) {
        return false;
      }

      final Map<dynamic, dynamic> friends = snapshot.value as Map;

      // Check if any friend has hasNewReviews flag set
      for (final entry in friends.values) {
        if (entry is Map) {
          final hasNewReviews = entry['hasNewReviews'];
          if (hasNewReviews == true) {
            return true; // Found new reviews delivered
          }
        }
      }

      return false;
    } catch (e) {
      appLog('Error checking new reviews delivered: $e');
      return false;
    }
  }

  Future<void> _checkNewReviewsDelivered() async {
    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return;
    }

    try {
      bool hasNewReviews = await _checkIfUserHasNewReviewsDelivered(userId);

      if (mounted) {
        setState(() {
          _hasNewReviewsDelivered = hasNewReviews;
        });
      }
    } catch (e) {
      appLog('Error checking new reviews delivered: $e');
    }
  }

  Future<void> _checkRequestedReviews() async {
    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return;
    }

    try {
      final DatabaseReference requestedRef = FirebaseDatabase.instance.ref(
        'users/$userId/reviews_requested',
      );
      final DataSnapshot snapshot = await requestedRef.get();

      if (mounted) {
        setState(() {
          _hasRequestedReviews =
              snapshot.exists &&
              snapshot.value is Map &&
              (snapshot.value as Map).isNotEmpty;
        });
      }
    } catch (e) {
      // Silently handle error - button just won't show
    }
  }

  Future<void> _loadAcceptsFriends() async {
    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _acceptsFriends = true;
        });
      }
      return;
    }

    try {
      bool accepts = true;
      try {
        final DataSnapshot s7 = await FirebaseDatabase.instance
            .ref('users/$userId/userSettings7')
            .get();
        if (s7.exists && s7.value != null) {
          final Object? v = s7.value;
          if (v is bool) {
            accepts = v;
          } else if (v is String) {
            accepts = v.toLowerCase() == 'true';
          } else if (v is num) {
            accepts = v != 0;
          }
        }
      } catch (e) {
        // keep default true
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _acceptsFriends = accepts;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      appLog('loadFriends error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStr.loadFriendsError)),
        );
      }
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);

    // Update review_info before signing out, but don't let it block sign-out
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final userEmail = SessionCache.userEmail;
    if (userId != null && userEmail.isNotEmpty) {
      try {
        final normalizedEmail = normalizeEmailForPath(userEmail);
        await updateReviewInfo(userId, normalizedEmail)
            .timeout(const Duration(seconds: 8));
        final today = DateTime.now().toIso8601String().substring(0, 10);
        await SessionCache.setReviewInfoLastUpdate(today);
        await SessionCache.setReviewsAdded(false);
      } catch (e) {
        appLog('Error updating review_info on sign out: $e');
        // Continue with sign-out regardless
      }
    }
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSigningOut = false);
      appLog('signOut error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStr.signOutFailed)));
      return;
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

  void _handleViewRequestedReviews() async {
    // Collect data and clear flags, then show toast after navigation
    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    String? toastMessage;
    
    if (userId != null) {
      toastMessage = await _collectAndClearNewReviewsFlags(userId);
    }

    if (!mounted) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewListScreen(
          mode: 'requested',
          toastMessage: toastMessage,
        ),
      ),
    );
    
    // After returning from the screen, refresh state
    if (mounted) {
      _checkNewReviewsDelivered();
      _checkRequestedReviews();
    }
  }

  /// Collect toast data, clear hasNewReviews flags, and return toast message
  Future<String?> _collectAndClearNewReviewsFlags(String uid) async {
    try {
      final DatabaseReference friendsRef = FirebaseDatabase.instance.ref(
        'users/$uid/friends',
      );
      final DataSnapshot snapshot = await friendsRef.get();

      if (!snapshot.exists ||
          snapshot.value == null ||
          snapshot.value is! Map) {
        return null;
      }

      final Map<dynamic, dynamic> friends = snapshot.value as Map;
      final Map<String, dynamic> updates = {};
      int totalNewReviews = 0;
      int totalDuplicates = 0;

      // Build update map to clear hasNewReviews flags and collect counts
      for (final MapEntry<dynamic, dynamic> entry in friends.entries) {
        final String friendUid = entry.key.toString();
        if (entry.value is Map) {
          final Map<dynamic, dynamic> friendData = entry.value as Map;
          final hasNewReviews = friendData['hasNewReviews'];
          if (hasNewReviews == true) {
            // Collect counts for toast
            if (friendData['newReviewsCount'] is int) {
              totalNewReviews += friendData['newReviewsCount'] as int;
            }
            if (friendData['duplicatesSkipped'] is int) {
              totalDuplicates += friendData['duplicatesSkipped'] as int;
            }
            
            // Clear flags
            updates['users/$uid/friends/$friendUid/hasNewReviews'] = null;
            updates['users/$uid/friends/$friendUid/newReviewsCount'] = null;
            updates['users/$uid/friends/$friendUid/duplicatesSkipped'] = null;
            updates['users/$uid/friends/$friendUid/newReviewsAt'] = null;
          }
        }
      }

      if (updates.isNotEmpty) {
        await FirebaseDatabase.instance.ref().update(updates);
        if (mounted) {
          setState(() {
            _hasNewReviewsDelivered = false;
          });
        }
        
        // Build and return toast message
        if (totalNewReviews > 0 && totalDuplicates > 0) {
          return 'Received $totalNewReviews new review${totalNewReviews == 1 ? '' : 's'} ($totalDuplicates duplicate${totalDuplicates == 1 ? '' : 's'} skipped)';
        } else if (totalNewReviews > 0) {
          return 'Received $totalNewReviews new review${totalNewReviews == 1 ? '' : 's'}';
        } else if (totalDuplicates > 0) {
          return 'All $totalDuplicates review${totalDuplicates == 1 ? '' : 's'} already exist';
        } else {
          return 'New reviews received';
        }
      }
      return null;
    } catch (e) {
      appLog('Error collecting and clearing new reviews flags: $e');
      // Clear stale indicator so UI doesn't stay stuck showing the badge
      if (mounted) {
        setState(() {
          _hasNewReviewsDelivered = false;
        });
      }
      return null;
    }
  }

  Future<void> _handleViewReviews() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = true;
    });

    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppStr.userNotAuthenticated)));
      }
      return;
    }

    final DatabaseReference reviewsRef = FirebaseDatabase.instance.ref(
      'users/$userId/reviews',
    );

    try {
      final DataSnapshot snapshot = await reviewsRef.get();

      if (mounted) {
        if (snapshot.exists && snapshot.value is Map) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ReviewListScreen(mode: 'list'),
            ),
          );
        } else {
          showDialog(
            context: context,
            builder: (_) {
              return AlertDialog(
                title: Text(AppStr.noReviewsTitle, style: AppFonts.bold),
                content: Text(
                  AppStr.noReviewsMessage,
                  style: AppFonts.standard,
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text(AppStr.ok, style: AppFonts.standard),
                  ),
                ],
              );
            },
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStr.loadReviewsError}: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startNewReview() {
    final ReviewContext newContext = ReviewContext(
      reviewMap: <String, dynamic>{},
      isEditing: false,
      reviewKey: null,
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GeneralScreen(context: newContext)),
    );
  }

  void _openFriends() {
    if (!_acceptsFriends) {
      return;
    }
    Navigator.pushNamed(context, '/friends').then((_) async {
      await _loadAcceptsFriends();
    });
  }

  void _openTestScreen() {
    final ReviewContext testContext = ReviewContext(
      reviewMap: <String, dynamic>{},
      isEditing: false,
      reviewKey: null,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TestGeneralScreen(context: testContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = SessionCache.userName.isNotEmpty
        ? SessionCache.userName
        : AppStr.anonUser;

    // Add (!) to friends label if there are pending mailbox requests
    String friendsLabel = AppStr.friendsUpper;
    if (_hasPendingMailboxRequests) {
      friendsLabel = '$friendsLabel (!)';
    }

    final Color friendsBg = _acceptsFriends
        ? AppColors.ochre
        : AppColors.greyShade400;
    final Color friendsFg = _acceptsFriends ? AppColors.black87 : AppColors.black38;

    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.darkGreen,
        title: Text(
          '${AppStr.appTitle} : $displayName',
          style: AppFonts.bold.copyWith(color: AppColors.white),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SizedBox(height: 24),
                  Text(
                    AppStr.restaurantReviews,
                    style: AppFonts.bold.copyWith(
                      fontSize: 24,
                      color: AppColors.red,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ochre,
                      foregroundColor: AppColors.black87,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _startNewReview,
                    child: Text(AppStr.addReview, style: AppFonts.standard),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9C27B0),
                      foregroundColor: AppColors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _openTestScreen,
                    child: Text('Test', style: AppFonts.standard.copyWith(color: AppColors.white)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.ochre,
                      foregroundColor: AppColors.black87,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleViewReviews,
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(AppStr.viewReviews, style: AppFonts.standard),
                  ),
                  if (_hasFriends) ...<Widget>[
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hasRequestedReviews
                            ? AppColors.ochre
                            : AppColors.greyShade400,
                        foregroundColor: AppColors.black87,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _hasRequestedReviews
                          ? _handleViewRequestedReviews
                          : null,
                      child: Text(
                        _hasNewReviewsDelivered
                            ? '${AppStr.friendReviewsButton} (!)'
                            : AppStr.friendReviewsButton,
                        style: AppFonts.standard,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: friendsBg,
                      foregroundColor: friendsFg,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _acceptsFriends ? _openFriends : null,
                    child: Text(
                      friendsLabel,
                      style: AppFonts.standard.copyWith(color: friendsFg),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 36),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings, color: AppColors.white),
                    label: Text(
                      AppStr.settings,
                      style: AppFonts.standard.copyWith(color: AppColors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.grey,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightBlueAccent,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pushNamed(context, '/help');
                    },
                    child: Text(
                      AppStr.help,
                      style: AppFonts.standard.copyWith(color: AppColors.white),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isSigningOut ? null : _signOut,
                    child: _isSigningOut
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : Text(
                            AppStr.signOut,
                            style: AppFonts.standard.copyWith(color: AppColors.white),
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
