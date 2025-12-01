/**
 * index.js
 * Cloud Functions entry point
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.acceptFriendRequest = functions.https.onCall(async (data, context) => {
  const { requestId, userId } = data;

  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "You must be signed in to accept a friend request."
    );
  }

  try {
    const db = admin.firestore();

    // Mark the request as accepted
    await db.collection("friendRequests").doc(requestId).update({
      status: "accepted",
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Optionally add to user's friends list
    await db.collection("users").doc(userId).update({
      friends: admin.firestore.FieldValue.arrayUnion(context.auth.uid),
    });

    return { success: true };
  } catch (error) {
    console.error("Error accepting friend request:", error);
    throw new functions.https.HttpsError("internal", "Failed to accept request");
  }
});
