const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

admin.initializeApp();

const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: "reducamark1@gmail.com",
    pass: "azqg qaec omkr pnt"
  }
});

exports.sendEmailOTP = functions.https.onCall(async (data, context) => {
  const email = data.email;

  const otp = Math.floor(100000 + Math.random() * 900000).toString();

  const hashedOtp = crypto
    .createHash("sha256")
    .update(otp)
    .digest("hex");

  await admin.firestore().collection("email_otps").doc(email).set({
    otp: hashedOtp,
    expiresAt: admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 5 * 60 * 1000)
    )
  });

  await transporter.sendMail({
    from: "GovPulse <YOUR_GMAIL@gmail.com>",
    to: email,
    subject: "Your Verification Code",
    text: `Your OTP is: ${otp}`
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