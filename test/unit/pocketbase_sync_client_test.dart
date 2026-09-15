import 'package:flutter_test/flutter_test.dart';
import 'package:taskframe/core/sync/pocketbase_sync_client.dart';

void main() {
  test('generatePairingCode returns 6 uppercase alphanumeric characters', () {
    final code = generatePairingCode();
    expect(code, hasLength(6));
    expect(RegExp(r'^[A-Z0-9]{6}$').hasMatch(code), isTrue);
  });

  test('generatePairingCode is not constant across calls', () {
    final codes = {for (var i = 0; i < 20; i++) generatePairingCode()};
    expect(codes.length, greaterThan(1));
  });
}
