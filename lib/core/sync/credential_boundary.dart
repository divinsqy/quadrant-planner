import 'dart:convert';

/// Auth sessions never enter this boundary. Reject credential-shaped structured
/// imports, including JSON stored inside a report/activity text column.
void rejectCredentialFields(Object? value, {int depth = 0}) {
  if (depth > 100) throw const FormatException('Data nesting limit');
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase().replaceAll(
        RegExp('[^a-z]'),
        '',
      );
      if ({
        'accesstoken',
        'refreshtoken',
        'sessiontoken',
        'authorization',
      }.contains(key)) {
        throw const FormatException('Credential field rejected');
      }
      rejectCredentialFields(entry.value, depth: depth + 1);
    }
  } else if (value is List) {
    for (final item in value) {
      rejectCredentialFields(item, depth: depth + 1);
    }
  } else if (value is String &&
      (value.trimLeft().startsWith('{') || value.trimLeft().startsWith('['))) {
    Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return;
    }
    rejectCredentialFields(decoded, depth: depth + 1);
  }
}
