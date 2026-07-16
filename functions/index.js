// Explicit v1 API: this codebase uses the v1 callable signature
// (data, context) and functions.runWith({ secrets }). In firebase-functions v7
// the bare "firebase-functions" root points at the v2 API instead, where the
// handler receives a single request object and .runWith does not exist — so we
// import the v1 namespace directly to keep the intended behaviour.
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

admin.initializeApp();

// Gmail credentials live in Secret Manager, never in source. Set them once with:
//   firebase functions:secrets:set GMAIL_USER
//   firebase functions:secrets:set GMAIL_PASS
// and bind them to the function via .runWith({ secrets: [...] }) below. Secrets
// are only injected at runtime, so the transporter is built lazily (not at module
// load, where process.env.GMAIL_* would still be undefined) and cached.
let _transporter;
function getTransporter() {
  if (_transporter) return _transporter;
  const user = process.env.GMAIL_USER;
  const pass = process.env.GMAIL_PASS;
  if (!user || !pass) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Email credentials are not configured (GMAIL_USER / GMAIL_PASS).",
    );
  }
  _transporter = nodemailer.createTransport({
    service: "gmail",
    auth: { user, pass },
  });
  return _transporter;
}

exports.sendEmailOTP = functions
  .runWith({ secrets: ["GMAIL_USER", "GMAIL_PASS"] })
  .https.onCall(async (data, context) => {
    const email = data.email;

    const otp = Math.floor(100000 + Math.random() * 900000).toString();

    const hashedOtp = crypto
      .createHash("sha256")
      .update(otp)
      .digest("hex");

    await admin.firestore().collection("email_otps").doc(email).set({
      otp: hashedOtp,
      expiresAt: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 5 * 60 * 1000),
      ),
    });

    await getTransporter().sendMail({
      from: `GovPulse <${process.env.GMAIL_USER}>`,
      to: email,
      subject: "Your Verification Code",
      text: `Your OTP is: ${otp}`,
    });

    return { success: true };
  });

exports.verifyEmailOTP = functions.https.onCall(async (data, context) => {
  const { email, otp } = data;

  const doc = await admin.firestore().collection("email_otps").doc(email).get();

  if (!doc.exists) {
    throw new functions.https.HttpsError("invalid-argument", "OTP not found");
  }

  const record = doc.data();

  if (record.expiresAt.toDate() < new Date()) {
    throw new functions.https.HttpsError("deadline-exceeded", "OTP expired");
  }

  const hashedOtp = crypto
    .createHash("sha256")
    .update(otp)
    .digest("hex");

  if (hashedOtp !== record.otp) {
    throw new functions.https.HttpsError("invalid-argument", "Invalid OTP");
  }

  await admin.firestore().collection("email_otps").doc(email).delete();

  return { verified: true };
});
