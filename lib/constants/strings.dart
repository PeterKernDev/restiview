// constants/strings.dart
// Centralized app strings used across the app.
// Keep keys stable for localization. Add new keys here as screens/features are added.
class AppStr {
  static const String countryMismatchTitle = 'Country Mismatch';
  static const String countryMismatchBody =
      'Your home country in settings does not match your current location. Please check your settings before continuing.';
  static const String countryMismatchUpdate = 'Update Home Country';
  static const String countryMismatchContinue = 'Continue Anyway';
  static const String releaseNumber = 'RestiView Release Number : ';
  static const String aboutDescription =
      'RestiView is a simple app which allows you to create and save your own personal restaurant reviews. Build up your own library and history of reviews and then search through to find your favourite restaurant next time you visit 🍽️ or scroll through to find the best place suited for a particular event.';
  static const String aboutTitle = 'About RestiView';
  static const String acceptTandCs = 'You must accept the Terms & Conditions';
  static const String acceptTermsLabel = 'Accept Terms & Conditions';
  static const String addPhoto = 'Add Photo';
  static const String add = 'ADD';
  static const String addReview = 'ADD REVIEW';
  static const String addressLabel = 'Address';
  static const String allFieldsRequired = 'All fields are required';
  static const String copiedToClipboard = 'Copied to clipboard';
  static const String ambianceLabel = 'Ambiance';
  static const String amountLabel = 'Amount';
  static const String appendedCustomValues =
      'Appended custom values from Firebase';
  static const String appTitle = 'RestiView';
  static const String autoFillFailed = 'Search failed – please enter manually.';
  static const String autoFillNone =
      'No restaurants found. Try searching again.';
  static const String autoFillSuccess = 'Auto-filled with nearby restaurant:';
  static const String restDetailsFound = 'Restaurant details found and filled in.';
  static const String restDetailsNotFound = 'Could not find restaurant details — please fill in manually.';
  static const String back = 'BACK';
  static const String bypassLogin = 'Bypass Login';
  static const String cancel = 'Cancel';
  static const String change = 'CHANGE';
  static const String cityHint = 'Enter city name (no suggestions available)';
  static const String cityLabel = 'City';
  static const String clear = 'CLEAR';
  static const String commentLabel = 'Comment';
  static const String commentsLabel = 'Comments';
  static const String commentsTitle = 'Comments';
  static const String confirmDelete = 'Yes';
  static const String costLabel = 'Cost';
  static const String locationLabel = 'Location';
  static const String cuisineLabel = 'Cuisine';
  static const String dateLabel = 'Date:';
  static const String defaultOccasion = 'Nothing Special';
  static const String delete = 'DELETE';
  static const String deletePendingMessage =
      'Discard your pending review and return to home?';
  static const String deletePermanentMessage =
      'This will permanently delete your review. Continue?';
  static const String deleteAccountSignedOut = 'Account deleted and signed out';
  static const String deleteTitle = 'Delete Review?';
  static const String deletePhotosLabel = 'Also delete photos from device';
  static const String photosWillBeDeleted =
      'photos will be permanently deleted from your device';
  static const String dinersLabel = 'Diners';
  static const String discardMessage =
      'Going back will discard all unsaved changes. Continue?';
  static const String discardTitle = 'Discard Changes?';
  static const String done = 'Done';
  static const String drinksLabel = 'Drinks';
  static const String duplicateMessageMiddle = 'on';
  static const String duplicateMessagePrefix = 'A review for';
  static const String duplicateMessageSuffix =
      'already exists.\nDo you still want to create a new one?';
  static const String duplicateTitle = 'Duplicate Review Detected';
  static const String emailLabel = 'Email Address';
  static const String emailNotFound = 'No account found for that email.';
  static const String emailPasswordRequired = 'Email and password are required';
  static const String emailRequired = 'Please enter a valid email address.';
  static const String emailIncorrect = 'The password you entered is incorrect.';
  static const String foodLabel = 'Food';
  static const String forgotPasswordLabel = 'Forgot Password?';
  static const String generalInfo = 'General Info';
  static const String goodForFilterPrompt = 'Select one or more filters:';
  static const String goodForFilterTitle = 'Filter by Good For';
  static const String goodForHeader = '============= Good For =============';
  static const String goodForPrompt =
      'Select what this restaurant is good for:';
  static const String goodForTitle = 'Good For';
  static const String help = 'HELP';
  static const String healingOrphanedAccount = 'Healing orphaned account';
  static const String homeCountryLabel = 'Home Country';
  static const String initializedDefaults = 'Initialized default custom values';
  static const String list = 'LIST';
  static const String michelinLabel = 'Michelin Stars:';
  static const String moreInfoPrompt = 'For more information, visit:';
  static const String multi = 'Multi';
  static const String nameHint = 'Name required for Registration';
  static const String nameLabel = 'Name';
  static const String next = 'NEXT';
  static const String noReviewsMessage =
      'You haven’t submitted any reviews yet.';
  static const String noReviewsTitle = 'No Reviews Found';
  static const String noLabel = 'No';
  static const String noTags = 'No tags selected';
  static const String notAvailable = 'Not available';
  static const String occasionLabel = 'Occasion';
  static const String ok = 'OK';
  static const String pageNotFound = 'Page not found';
  static const String patchedBaseCountry =
      'Patched baseCountry for legacy user';
  static const String passwordLabel = 'Password';
  static const String phoneLabel = 'Telephone';
  static const String photoDisabled = 'Photo access is disabled in settings.';
  static const String photoError = 'Photo not found';
  static const String pickDate = 'Pick Date';
  static const String lowStorageTitle = 'Low Storage Space';
  static const String lowStorageMessage = 'You have only';
  static const String lowStorageMB =
      'MB of free space remaining. Saving this review may fail if storage runs out.';
  static const String continueAnyway = 'Continue Anyway';
  static const String preview = 'PREVIEW';
  static const String previewTitle = 'RestiView – Preview';
  static const String proceed = 'Proceed';
  static const String quit = 'QUIT';
  static const String rateSubtitle = 'Rate Each Category';
  static const String rateTitle = 'Rate the Restaurant';
  static const String ratingsHeader = '============= Ratings =============';
  static const String registerButton = ' - REGISTER -';
  static const String registerTitle = 'Register';
  static const String registrationFailed = 'Registration Failed';
  static const String registrationDbError = 'Registration could not be completed. Please try again.';
  static const String networkError = 'No internet connection. Please check your network and try again.';
  static const String emailAlreadyInUse = 'An account already exists for that email address. Please sign in instead.';
  static const String weakPassword = 'Password is too weak. Please choose a stronger password (at least 6 characters).';
  static const String removePhoto = 'Remove';
  static const String removeButton = 'REMOVE';
  static const String restaurantLabel = 'Restaurant';
  static const String restaurantRequired = 'Restaurant name is required';
  static const String restaurantReviews = 'Restaurant Reviews';
  static const String reviewDeleted = 'Review deleted';
  static const String reviewSaved = 'Review saved successfully';
  static const String save = 'SAVE';
  static const String search = 'Search';
  static const String selectRestaurant = 'Select a Restaurant';
  static const String serviceLabel = 'Service';
  static const String settings = 'SETTINGS';
  static const String signInButton = '- SIGN IN -';
  static const String signInFailed = 'Sign In Failed';
  static const String signInRegister = 'SIGN IN / REGISTER';
  static const String signInTitle = 'Sign In';
  static const String signOut = 'SIGN OUT';
  static const String staySignedIn = 'Stay Signed In';
  static const String subtitle =
      'Record your most memorable dining experiences.';
  static const String totalRatingLabel = 'Restaurant Rating:';
  static const String unknown = 'Unknown';
  static const String userNotAuthenticated = 'User not authenticated';
  static const String vfmsLabel = 'VFM';
  static const String vfmText = 'Value For Money';
  static const String viewReviews = 'VIEW REVIEWS';
  static const String viewTermsLabel = 'View Terms & Conditions';
  static const String websiteUrl = 'www.restiview.com';
  static const String welcomeMessage =
      'Welcome to RestiView\nPlease sign in or register.';
  static const String yes = 'Yes';
  static const String sortByLabel = 'Sort By';
  static const String apply = 'Apply';
  static const String noReviewsMatch =
      'No reviews match the search/filter settings';
  static const String sortOptionDate = 'Date';
  static const String sortOptionRating = 'Rating';
  static const String sortOptionName = 'Name';
  static const String ratingThresholdLabel = 'Minimum Rating';
  static const String sortLabel = 'Sort:';
  static const String ratingLabel = 'Rating:';
  static const String anyValue = 'Any';
  static const String settingsTitle = 'RestiView - Settings';
  static const String defaultSearchFilters = 'Default Search Filters';
  static const String allowLocationLabel = 'Allow Location Services';
  static const String searchRadiusLabel = 'Search Radius (meters)';
  static const String allowPhotosLabel = 'Allow Access to Photos';
  static const String allowAutoCaptureLabel = 'Allow Auto Capture';
  static const String allowAutoCaptureSubtitle =
      'Automatically detect restaurants';
  static const String customValuesButton = 'CUSTOM VALUES';
  static const String saveChangesButton = 'SAVE';
  static const String resetButton = 'RESET';
  static const String resetSettingsTitle = 'Reset Settings';
  static const String resetSettingsMessage = 'Are you sure you want to reset the settings values?';
  static const String sortOptionCity = 'City';
  static const String sortOptionCuisine = 'Cuisine';
  static const String customValuesTitle = 'Custom Values';
  static const String cuisineMaxLength = 'Cuisine max 24 characters';
  static const String occasionMaxLength = 'Occasion max 24 characters';
  static const String alreadyExists = 'already exists';
  static const String addedToCuisines = 'added to custom cuisines';
  static const String addedToOccasions = 'added to custom occasions';
  static const String addedToCountries = 'added to your countries';
  static const String notApprovedCountry =
      'is not in the approved country list';
  static const String alreadyInList = 'is already in your list';
  static const String builtInValue =
      'is a built-in value and cannot be removed';
  static const String usedInReview =
      'is used in a review and cannot be removed';
  static const String valueUsedInReview =
      'Value cannot be changed or removed — it is used in a review';
  static const String hasBeenRemoved = 'has been removed';
  static const String backToSettings = 'BACK TO SETTINGS';
  static const String goToTop = 'GO TO TOP';
  static const String addCuisine = 'ADD CUISINE';
  static const String removeCuisine = 'REMOVE CUISINE';
  static const String addOccasion = 'ADD OCCASION';
  static const String removeOccasion = 'REMOVE OCCASION';
  static const String addCountry = 'ADD COUNTRY';
  static const String currentCuisinesLabel = 'Current Cuisines';
  static const String currentOccasionsLabel = 'Current Occasions';
  static const String deleteAccountButton = '* DELETE ACT *';
  static const String settingsSaved = 'Settings saved';
  static const String deleteAccountTitle = 'Delete Account';
  static const String deleteAccountConfirm =
      'Are you sure? This cannot be undone.';
  static const String deleteAccountSuccess = 'Account deleted';
  static const String deleteAccountError = 'Error deleting account';
  static const String resetLinkSent = 'Reset link sent to';
  static const String resetLinkError = 'Error sending reset link';
  static const String emailFormatInvalid = 'Please enter a valid email address';
  static const String enableResetToggleLabel = 'Enable password reset';
  static const String signInError = 'Sign-in failed';
  static const String confirm = 'Confirm';
  static const String newCuisineHint = 'Enter new cuisine (max 24 characters)';
  static const String cuisineAdded = 'Cuisine added successfully';
  static const String cuisineExists = 'This cuisine already exists';
  static const String cuisineInvalid = 'Cuisine must be 1–24 characters';
  static const String builtInBlock =
      'This is a built-in value and cannot be removed.';
  static const String usedBlock =
      'This cuisine is used in a review and cannot be removed.';
  static const String cuisineRemoved = 'Cuisine has been removed.';
  static const String builtInCuisineBlock =
      'This is a built-in cuisine and cannot be removed.';
  static const String cuisineRequired = 'Please enter a cuisine name';
  static const String saveError = 'Save failed';
  static const String signUpFailed = 'Sign up failed';
  static const String resetEmailSent = 'Password reset email sent';
  static const String resetFailed = 'Password reset failed';
  static const String anonUser = 'Guest';
  static const String loadReviewsError = 'Failed to load reviews';
  static const String signOutFailed = 'Sign out failed';
  static const String newOccasionHint =
      'Enter a new occasion (max 24 characters)';
  static const String newCuisineLabel = 'New Cuisine';
  static const String editCuisineLabel = 'Edit Cuisine';
  static const String edit = 'EDIT';
  static const String updateSuccess = 'updated successfully';
  static const String updatedCuisine = 'has been updated';
  static const String enterCustomCuisine = 'Please enter a custom cuisine';
  static const String enterCustomOccasion = 'Please enter a custom occasion';
  static const String updatedOccasion = 'has been updated';
  static const String editOccasionLabel = 'Edit occasion';
  static const String detailsMenuTitle = 'Details';
  static const String cocktails = 'Cocktails';
  static const String starters = 'Starters';
  static const String wine = 'Wine';
  static const String mainCourse = 'Main course';
  static const String dessert = 'Dessert';
  static const String otherDrinks = 'Other drinks';
  static const String detailsNone = 'No items';
  static const String detailsCountPrefix = 'Items';
  static const String detailsCountSuffix = 'items';
  static const String open = 'Open';
  static const String addMore = '+More';
  static const String itemNameHint = 'Details';
  static const String photoAttached = 'Photo attached';
  static const String noPhoto = 'No photo';
  static const String detailsSaved = 'Details saved';
  static const String remove = 'Remove';
  static const String detailsNoText = 'No description';
  static const String detailsAddLabel = 'Add item';
  static const String detailsAddHint = 'Describe this item (optional)';
  static const String maxRating = '100';
  static const String logoSemanticLabel = 'RestiView logo';
  static const String invalidUrl = 'Unable to open link on this device';
  static const String openUrlFailed = 'Failed to open link, please try again';
  static const String enterCustomCountry =
      'Please select a country before adding';
  static const String sortFilter = 'Sort/Filter';
  static const String loadFailed = 'Failed to load reviews';
  static const String reviewLoadError = 'Unable to load review data';
  static const String autoFillSkipped =
      'Location search skipped — allowLocation is false.';
  static const String locationDisabled =
      'Location services are disabled. Please enable them in Settings.';
  static const String permissionDeniedForever =
      'Location permission permanently denied. Enable it in app settings.';
  static const String permissionDenied =
      'Location permission denied. Cannot auto-fill.';
  static const String searchFailed = 'Search failed';
  static const String locationSearchLabel = 'Location search : ';

  static const String friendsTitle = 'Friends';
  static const String noFriends = 'No friends found';
  static const String addFriend = '+FRIEND';
  static const String friendRequestsDisabled =
      'User does not accept friend requests';
  static const String sendFriendRequest = 'SEND FRIEND REQUEST';
  static const String friendTap = 'Open request details';

  static const String frAsked = 'FR-ASKED';
  static const String frWants = 'FR-WANTS';
  static const String rvAsked = 'RV-ASKED';
  static const String rvWants = 'RV-WANTS';
  static const String rvProvidedLabel = 'RV-PROVIDED';
  static const String rvDeclinedLabel = 'RV-DECLINED';

  static const String declined = 'DECLINED';
  static const String rejected = 'REJECTED';
  static const String timedOut = 'TIMED-OUT';

  static const String sharedCountFmt = '(%d)';
  static const String loadFriendsError = 'Failed to load friends';
  static const String friendsUpper = 'FRIENDS';
  static const String friendsCountFmt = 'FRIENDS (%d)';
  static const String requestTitle = 'Friend Request';
  static const String sendRequestTitle = 'Send Friend Request';
  static const String userNameLabel = 'User Name';
  static const String sendRequest = 'SEND';
  static const String friendRequestSent = 'Friend request sent';
  static const String sendRequestFailed = 'Failed to send request';
  static const String userNotFound = 'User not found';
  static const String accept = 'ACCEPT';
  static const String hardReject = 'HARD REJECT';
  static const String softReject = 'SOFT REJECT';
  static const String friendAccepted = 'Friend request accepted';
  static const String acceptFailed = 'Failed to accept request';
  static const String friendRejected = 'Friend request processed';
  static const String friendRejectedInform =
      'Friend request rejected and user informed';
  static const String friendDeclinedInform =
      'Friend request declined and user informed';
  static const String rejectFailed = 'Failed to reject request';
  static const String informOnRejectLabel = 'Inform user of rejection';
  static const String invalidEmail = 'Enter a valid email address';
  static const String fromLabel = 'From';
  static const String check = "Check";
  static const String emailValid = "Email is valid";
  static const String checkFailed = "Email check failed";
  static const String emailNotChecked = "Please check the email before sending";
  static const String friendRequestNoticesProcessed =
      "Friend request notices processed";
  static const String mappingWriteFailed = "Failed to ensure email mapping";
  static const String signInRequired = 'Please sign in to continue';
  static const String cannotAddSelf = 'You cannot add yourself as a friend';
  static const String requestSent = 'Review request sent';
  static const String requestSendFailed = 'Failed to send review request';
  static const String requestsTitle = 'Requests';
  static const String requestCommentLabel = 'Comment (optional)';
  static const String validEmailConfirmed = 'valid email confirmed';
  static const String checkLabel = 'Check';
  static const String noFriendsYet = 'No friends yet';
  static const String accepting = 'Accepting...';
  static const String reject = 'DECLINE';
  static const String friendLabel = 'FRIEND';
  static const String alreadyFriends = 'You are already friends';
  static const String userNotAvailable = 'User not available';
  static const String incomingRequestsTitle = 'Incoming requests';
  static const String currentFriendsTitle = 'Your friends';
  static const String requestReceivedLabel = 'Wants to be your friend';
  static const String acceptLabel = 'Accept';
  static const String rejectLabel = 'Reject';
  static const String recipientLabel = 'Recipient';
  static const String recipientHint = 'recipient@example.com';
  static const String recipientRequired = 'Recipient email is required';
  static const String selectedIdPrefix = 'Selected id:';
  static const String clearRecipientTooltip = 'Clear recipient';
  static const String noRecipientSelected = 'No recipient selected';
  static const String countryLabel = 'Country';
  static const String countryRequired = 'Country is required';
  static const String requesterLabel = 'Requester';
  static const String recipientLabelShort = 'Recipient';
  static const String messageLabel = 'Message';
  static const String notProvided = 'Not provided';
  static const String createdAtLabel = 'Created';
  static const String deleteSuccess = 'Friendship removed';

  static const String deleteSuccessPending = 'Friendship removal initiated';
  static const String deleteFailed = 'Failed to remove friendship';
  static const String allowFriendsLabel = 'Allow Friends';
  static const String reviewRequestDetailsTitle = 'Review Request Details';
  static const String requestingEmail = 'Req Email';
  static const String requestingUsername = 'Req User';
  static const String requestingComment = 'Comment';
  static const String filtersLabel = 'Request Breakdown:';
  static const String reviewMatchingCountLabel = 'Reviews matching criteria';
  static const String reviewsApprovedLabel = 'Reviews approved';
  static const String reviewsExcludedLabel = 'Reviews excluded';
  static const String filterColReviews = 'Reviews';
  static const String filterAllCities = '<all>';
  static const String includePhotosLabel = 'Include photos?';
  static const String providerCommentLabel = 'Provider comment (optional)';
  static const String providerCommentHint = 'Optional message to requester';
  static const String backButtonLabel = 'Back';
  static const String acceptButtonLabel = 'Accept';
  static const String rejectButtonLabel = 'Reject';
  static const String reviewButtonLabel = 'Review';
  static const String unknownCount = 'unknown';
  static const String none = 'None';

  static const String reviewReviewsTitle = 'Review reviews';
  static const String matchingReviews = 'Matches';
  static const String includedLabel = 'Included';
  static const String excludedLabel = 'Excluded';
  static const String noMatchingReviews = 'No matching reviews';
  static const String foundMatchesFmt = 'Found %d matching reviews.';
  static const String foundMatchesLimitedFmt =
      'Found %d matching reviews. Only the first 50 will be shared.';
  static const String reviewsSelected = 'Reviews Selected:';
  static const String selectAll = 'Select All';
  static const String noReviewsAvailable =
      'No reviews available from this user';
  static const String requestReviewsTitle = 'Request Reviews';
  static const String toLabel = 'To:';
  static const String noMatchingReviewsCannotAccept =
      'No matching reviews found; cannot accept this request.';

  static const String exclude = 'Exclude';
  static const String include = 'Include';
  static const String declineLabel = 'DECLINE';
  static const String deleteLabel = 'DELETE';
  static const String reviewLabel = 'REVIEW';
  static const String backLabel = 'BACK';
  static const String decline = 'Decline';
  static const String frWantedLabel = 'FR-WANTED';
  static const String frAskedLabel = 'FR-ASKED';
  static const String rvWantsLabel = 'RV-WANTS';
  static const String rvAskedLabel = 'RV-ASKED';
  static const String declinedLabel = 'DECLINED';
  static const String unknownLabel = 'UNKNOWN';

  // Additional friend/review request strings
  static const String validEmailAddress = 'Valid email address';
  static const String declineAcknowledged = 'Decline acknowledged';
  static const String declineProvidedReviewsTitle = 'Decline Provided Reviews';
  static const String declineReviewRequestTitle = 'Decline Review Request';
  static const String declineReviewRequestMessage =
      'Are you sure you want to decline this review request? You can optionally provide a message to the requester:';
  static const String optionalDeclineMessageHint =
      'Optional decline message (max 30 characters)';

  // Auto-save / draft
  static const String autoSaved = 'Review auto-saved';
  static const String draftResumeTitle = 'Unsaved Draft Found';
  static const String draftResumeMessage =
      'You have an unsaved draft for "%s". Would you like to resume editing it?';
  static const String draftResume = 'Resume';
  static const String draftDiscard = 'Discard';
  static const String deleteFriendTitle = 'Delete Friend';
  static const String friendReviewsButton = 'FRIEND REVIEWS';
  static const String selectLocationRequired =
      'Please select at least one country or city';
  
  // Friend deletion and decline confirmations (Phase 1-4)
  static const String retractFriendRequest =
      'Retract this friend request? The other user will be notified that it was declined.';
  static const String deleteDeclinedFriendInstigator =
      'You declined this friend relationship. If you delete this record, this user will be able to send you a new friend request. Confirm deletion?';
  static const String deleteDeclinedFriendRecipient =
      'This friend declined your request. If you send another friend request to this user, it will probably be automatically declined. Confirm deletion?';
  static const String declineEstablishedFriendTitle = 'Decline Friend';
  static const String declineEstablishedFriendMessage =
      'Are you sure you want to decline this established friend relationship? This will change the status to declined.';

  // Settings screen
  static const String accountDeletionCancelledPassword =
      'Account deletion cancelled - password required';
  static const String confirmPasswordTitle = 'Confirm Password';
  static const String confirmDeletePasswordPrompt =
      'For security, please enter your password to confirm account deletion:';
  static const String cannotDisableFriendsTitle = 'Cannot Disable Friends';
  static const String deleteDeclinedFriendsConfirmTitle =
      'Delete Declined Friends?';
  static const String errorCheckingFriends = 'Error checking friends';
  static const String deletionFarewellTitle = 'We are sorry to see you go';
  static const String deletionFarewellPrompt =
      'If you wish, please let us know why you are deleting your account (optional):';
  static const String deletionReasonHint = 'Reason (optional)';
  static const String continueButton = 'Continue';

  // List screen
  static const String updatingReviewInfo = 'Updating review info...';
  static const String noReviewsToDelete = 'No reviews to delete';
  static const String deleteReviewsTitle = 'Delete Reviews';
  static const String errorDeletingReviews = 'Error deleting reviews';

  // Custom values screen
  static const String selectCuisineToEdit =
      'Please select a cuisine to edit';
  static const String valueUnchanged = 'Value unchanged';
  static const String notSignedIn = 'Not signed in';
  static const String noCustomValuesToEdit =
      'No custom values found to edit';
  static const String selectedCuisineNotFound = 'Selected cuisine not found';
  static const String selectOccasionToEdit =
      'Please select an occasion to edit';
  static const String selectedOccasionNotFound =
      'Selected occasion not found';
  static const String selectCuisineHint = 'Select cuisine';
  static const String selectOccasionHint = 'Select occasion';
  static const String selectCountryHint = 'Select country';

  // Friends screen
  static const String errorGatheringReviews = 'Error gathering reviews';
  static const String featureNotAvailable = 'This feature is not available';
  static const String reviewRequestDeclined = 'Review request declined';
  static const String rvRequestLabel = 'RV-REQUEST';
  static const String addReviewsLabel = '+Reviews';
  static const String deleteRelationshipFallback =
      'Are you sure you want to delete this friend relationship?';

  // Review request screen
  static const String requestBtnLabel = 'REQUEST';

  // Help screen — user guide
  static const String userGuideTitle = 'User Guide';
  static const String userGuideLinkPrompt = 'For the full guide and support, visit:';

  static const String helpGettingStartedTitle = 'Getting Started';
  static const String helpGettingStartedBody =
      'Create a free account by tapping REGISTER on the home screen. '
      'Enter your email, password, name, and home country, then accept '
      'the Terms & Conditions.\n\n'
      'On subsequent visits tap SIGN IN. Tick "Stay Signed In" to have '
      'your credentials remembered automatically.\n\n'
      'If you forget your password, tap "Forgot Password?" on the sign-in '
      'screen and a reset link will be sent to your email address.';

  static const String helpAddingReviewTitle = 'Adding a Review';
  static const String helpAddingReviewBody =
      'Tap ADD REVIEW on the home screen to start a new review. '
      'The wizard has four steps:\n\n'
      '1. General Info — Enter the restaurant name, city, country, cuisine, '
      'occasion, date, number of diners, and cost. If location services are '
      'enabled the app can auto-fill restaurant details from nearby places.\n\n'
      '2. Comments — Add free-text notes and optional meal details '
      '(starters, mains, desserts, drinks). You can attach a photo to each item.\n\n'
      '3. Ratings — Rate the restaurant 0–5 stars across Food, Service, '
      'Ambiance, Drinks, and Value For Money. You can also record Michelin stars.\n\n'
      '4. Good For — Tag the restaurant with categories like "Date Night", '
      '"Business Lunch", or "Large Groups" to make it easier to find later.\n\n'
      'Tap PREVIEW at any point to review your entry, then SAVE on the '
      'preview screen to store it permanently.';

  static const String helpViewingReviewsTitle = 'Viewing & Searching Reviews';
  static const String helpViewingReviewsBody =
      'Tap VIEW REVIEWS on the home screen to see all your saved reviews.\n\n'
      'Use the Sort/Filter button to:\n'
      '• Sort by Date, Rating, Name, or City\n'
      '• Filter by Country, City, or Cuisine\n'
      '• Set a minimum star rating\n\n'
      'Tap the Good For chip to filter by occasion tags (e.g. show only '
      '"Brunch" restaurants).\n\n'
      'Tap any review card to open the full preview. From there you can '
      'EDIT the review or DELETE it.';

  static const String helpFriendsTitle = 'Friends';
  static const String helpFriendsBody =
      'The Friends feature lets you connect with other RestiView users '
      'and share reviews.\n\n'
      'To add a friend, tap FRIENDS on the home screen, then tap +FRIEND '
      'and enter their email address. They will receive a notification the '
      'next time they open the app.\n\n'
      'When you have an incoming friend request, the FRIENDS button shows '
      'a (!) badge. Open Friends, select the request row, and tap ACCEPT '
      'or DECLINE.\n\n'
      'Note: A user must have "Allow Friends" enabled in their Settings '
      'before you can send them a request.';

  static const String helpReviewRequestsTitle = 'Review Requests';
  static const String helpReviewRequestsBody =
      'Once you are friends with another user you can request copies of '
      'their reviews — useful when visiting a city they know well.\n\n'
      'To send a request:\n'
      '1. Open Friends and select a friend.\n'
      '2. Their review countries and cities are shown — tick the ones you '
      'want and tap REQUEST.\n\n'
      'To provide reviews when you receive a request:\n'
      '1. A (!) badge appears on FRIENDS — tap it to see the request.\n'
      '2. Tap the request row to see the details and how many of your '
      'reviews are in scope.\n'
      '3. Tap REVIEW to go through each one and choose to include or exclude it.\n'
      '4. Tap ACCEPT to deliver the approved reviews.\n\n'
      'Delivered reviews appear under REQUESTED REVIEWS on the '
      'requester\'s home screen.';

  static const String helpSettingsTitle = 'Settings';
  static const String helpSettingsBody =
      '• Sort By — The default sort order for your review list (Rating, Date, Name, City, or Cuisine).\n\n'
      '• Home Country — Your default country when creating reviews. The app '
      'will alert you if your GPS location differs from this setting.\n\n'
      '• Allow Location Services — Enables the app to auto-fill restaurant '
      'details and detect nearby restaurants when adding a new review.\n\n'
      '• Search Radius — How far (in metres) the location search looks for '
      'nearby restaurants when auto-filling details (10–200 m).\n\n'
      '• Allow Photos — Enables photo attachments on review detail cards.\n\n'
      '• Allow Friends — Controls whether other users can send you friend '
      'or review requests. You cannot turn this off while you have active '
      'friends — declined relationships must be cleared first.\n\n'
      '• Allow Auto Capture — Automatic location-based review capture '
      '(coming soon — currently inactive).\n\n'
      '• Custom Values — Opens a separate screen where you can define your '
      'own Cuisine types, Occasion tags, and Countries to appear in dropdowns '
      'throughout the app.\n\n'
      '• Reset Settings — Returns all settings to their default values.\n\n'
      '• Save Changes — Persists all changes to the server. '
      'Settings are not saved until this button is tapped.\n\n'
      '• Delete Account — Permanently removes your account and all associated '
      'data. This action cannot be undone.';

  // Dynamic strings (methods for interpolated values)
  static String sendNReviews(int count) => 'Send $count reviews?';
  static String reviewsDeletedSuccess(int count) =>
      '$count review(s) deleted successfully';

  // Sort/filter UI
  static const String filterAllFriends = 'ALL';
  static const String clearIcon = '<C>';

  // Confirm/decline dialogs
  static const String declineReviewRequestConfirm = 'Decline review request?';
  static const String friendDeclined = 'Friend declined';

  // Multi-restaurant selector warning
  static const String multiOverwriteTitle = 'Replace Entered Data?';
  static const String multiOverwriteBody =
      'You have already entered data in this form. Selecting a restaurant from the list will overwrite it. Continue?';
  static const String multiOverwriteConfirm = 'Yes, Replace';
}
