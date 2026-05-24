//
// lib/sub_friends_screen/friend_actions.dart
// Action area used by FriendsScreen.
// Layout: two rows
//  - Row 1: Accept | Decline | Delete
//  - Row 2: Back | +Friend
// Buttons receive enabled/loading flags and callbacks from parent.

import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../constants/fonts.dart';
import '../constants/strings.dart';

class FriendActions extends StatelessWidget {
  const FriendActions({
    super.key,
    required this.acceptEnabled,
    required this.declineEnabled,
    required this.deleteEnabled,
    required this.accepting,
    required this.declining,
    required this.deleting,
    required this.onAccept,
    required this.onDecline,
    required this.onDelete,
    required this.onBack,
    required this.onAddFriend,
    required this.addFriendLabel,
  });

  final bool acceptEnabled;
  final bool declineEnabled;
  final bool deleteEnabled;
  final bool accepting;
  final bool declining;
  final bool deleting;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onDelete;
  final VoidCallback onBack;
  final VoidCallback onAddFriend;
  final String addFriendLabel;

  // Shared base style copied from RatingsScreen actionBtnBase
  ButtonStyle _actionBtnBaseStyle(
    Color backgroundColor,
    Color foregroundColor,
  ) {
    return ElevatedButton.styleFrom(
      textStyle: AppFonts.bold.copyWith(fontSize: 14, letterSpacing: 0.4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      minimumSize: const Size(0, 44),
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback? onPressed,
    required Color activeColor,
    required bool loading,
    required Color textColor,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
        child: ElevatedButton(
          onPressed: onPressed,
          style: _actionBtnBaseStyle(
            onPressed != null ? activeColor : AppColors.grey,
            textColor,
          ),
          child: SizedBox(
            height: 20,
            child: Center(
              child: loading
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(textColor),
                      ),
                    )
                  : Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.bold.copyWith(color: textColor),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Row 1: Accept | Decline | Delete
    // Accept = green, Decline = red, Delete = blueAccent (unchanged)
    final Widget acceptBtn = _actionButton(
      label: AppStr.acceptLabel,
      onPressed: acceptEnabled ? onAccept : null,
      activeColor: AppColors.darkGreen,
      loading: accepting,
      textColor: AppColors.white,
    );

    final Widget declineBtn = _actionButton(
      label: AppStr.declineLabel,
      onPressed: declineEnabled ? onDecline : null,
      activeColor: AppColors.red,
      loading: declining,
      textColor: AppColors.white,
    );

    final Widget deleteBtn = _actionButton(
      label: AppStr.deleteLabel,
      onPressed: deleteEnabled ? onDelete : null,
      activeColor: AppColors.btnDelete,
      loading: deleting,
      textColor: AppColors.btnText,
    );

    // Row 2: Back | +Friend
    // Back = ochre, +Friend uses provided addFriendLabel (text from caller)
    final Widget backBtn = Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
        child: ElevatedButton(
          onPressed: onBack,
          style: _actionBtnBaseStyle(AppColors.ochre, AppColors.black),
          child: Text(
            AppStr.backLabel,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.bold.copyWith(color: AppColors.black),
          ),
        ),
      ),
    );

    final Widget addFriendBtn = Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
        child: ElevatedButton(
          onPressed: onAddFriend,
          style: _actionBtnBaseStyle(AppColors.yellow, AppColors.black),
          child: Text(
            addFriendLabel,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.bold.copyWith(color: AppColors.black),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.transparent,
      child: Column(
        children: <Widget>[
          Row(children: <Widget>[acceptBtn, declineBtn, deleteBtn]),
          Row(children: <Widget>[backBtn, addFriendBtn]),
        ],
      ),
    );
  }
}
