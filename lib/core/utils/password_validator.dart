class PasswordValidator {
  static bool hasMinLength(String password) {
    return password.length >= 8;
  }

  static bool hasUpper(String password) {
    return password.contains(RegExp(r'[A-Z]'));
  }

  static bool hasNumber(String password) {
    return password.contains(RegExp(r'[0-9]'));
  }

  static bool hasSpecial(String password) {
    return password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
  }

  static int strengthScore(String password) {
    int score = 0;

    if (hasMinLength(password)) score++;
    if (hasUpper(password)) score++;
    if (hasNumber(password)) score++;
    if (hasSpecial(password)) score++;

    return score;
  }
}
