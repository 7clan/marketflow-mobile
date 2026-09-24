import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('accepts a normal address', () {
      expect(Validators.email('dana@marketflow.dev'), isNull);
    });

    test('accepts plus addressing and trims whitespace', () {
      expect(Validators.email('  dana.m+shop@example.co '), isNull);
    });

    test('rejects empty input with a required message', () {
      expect(Validators.email(null), 'Email is required.');
      expect(Validators.email('   '), 'Email is required.');
    });

    test('rejects a missing domain', () {
      expect(
        Validators.email('dana@localhost'),
        'Enter a valid email address.',
      );
    });

    test('rejects a missing TLD', () {
      expect(
        Validators.email('dana@marketflow'),
        'Enter a valid email address.',
      );
    });

    test('rejects garbage input', () {
      expect(Validators.email('not-an-email'), 'Enter a valid email address.');
    });
  });

  group('Validators.password', () {
    test('accepts 8 or more characters', () {
      expect(Validators.password('Password123'), isNull);
      expect(Validators.password('12345678'), isNull);
    });

    test('rejects empty input', () {
      expect(Validators.password(null), 'Password is required.');
      expect(Validators.password(''), 'Password is required.');
    });

    test('rejects fewer than 8 characters', () {
      expect(Validators.password('Abc123!'), 'Use at least 8 characters.');
    });
  });

  group('Validators.requiredField', () {
    test('accepts non-blank text and trims', () {
      expect(Validators.requiredField(' hello '), isNull);
    });

    test('rejects null and whitespace with the field label', () {
      expect(
        Validators.requiredField(null, label: 'City'),
        'City is required.',
      );
      expect(
        Validators.requiredField('   ', label: 'City'),
        'City is required.',
      );
    });
  });

  group('Validators.name', () {
    test('accepts letters, spaces, apostrophes and hyphens', () {
      expect(Validators.name("Anne-Marie O'Neil"), isNull);
      expect(Validators.name('José Álvarez'), isNull);
    });

    test('rejects empty input', () {
      expect(Validators.name(''), 'Name is required.');
    });

    test('rejects a single character', () {
      expect(Validators.name('A'), 'Name is too short.');
    });

    test('rejects digits and symbols', () {
      expect(
        Validators.name('Dana123'),
        "Use letters, spaces, apostrophes or hyphens only.",
      );
    });
  });

  group('Validators.street', () {
    test('accepts a realistic street address', () {
      expect(Validators.street('482 Harbor Lane, Apt 3'), isNull);
    });

    test('rejects empty input', () {
      expect(Validators.street(null), 'Street address is required.');
    });

    test('rejects too-short input', () {
      expect(Validators.street('1 A'), 'Enter a complete street address.');
    });

    test('rejects special characters like semicolons', () {
      expect(
        Validators.street('482 Harbor Lane; DROP'),
        'Avoid special characters in the address.',
      );
    });
  });

  group('Validators.city', () {
    test('accepts a real city name', () {
      expect(Validators.city('Portland'), isNull);
    });

    test('rejects empty input', () {
      expect(Validators.city(''), 'City is required.');
    });

    test('rejects a single letter', () {
      expect(Validators.city('A'), 'Enter a valid city.');
    });
  });

  group('Validators.region', () {
    test('accepts two-letter states and full names', () {
      expect(Validators.region('OR'), isNull);
      expect(Validators.region('Oregon'), isNull);
    });

    test('rejects empty input', () {
      expect(Validators.region(''), 'State is required.');
    });

    test('rejects a single character', () {
      expect(Validators.region('O'), 'Enter a valid state.');
    });
  });

  group('Validators.zipCode', () {
    test('accepts 5-digit and alphanumeric postal codes', () {
      expect(Validators.zipCode('97201'), isNull);
      expect(Validators.zipCode('SW1A 1AA'), isNull);
    });

    test('rejects empty input', () {
      expect(Validators.zipCode(''), 'ZIP code is required.');
    });

    test('rejects too-short input', () {
      expect(Validators.zipCode('9'), 'Enter a valid ZIP code.');
    });

    test('rejects symbols', () {
      expect(Validators.zipCode('#!abc'), 'Enter a valid ZIP code.');
    });
  });

  group('Validators.phone', () {
    test('accepts formatted numbers with and without country code', () {
      expect(Validators.phone('+1 503 555 0148'), isNull);
      expect(Validators.phone('503-555-0148'), isNull);
    });

    test('rejects empty input', () {
      expect(Validators.phone(''), 'Phone number is required.');
    });

    test('rejects letters', () {
      expect(Validators.phone('503 CALL NOW'), 'Enter a valid phone number.');
    });

    test('rejects too-few digits', () {
      expect(Validators.phone('555'), 'Enter a valid phone number.');
    });
  });
}
