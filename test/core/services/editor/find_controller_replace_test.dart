import 'package:code_forge/code_forge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expands numbered regex replacement groups', () {
    final match = RegExp(r'([a-z])=(\d)').firstMatch('x=1')!;

    expect(FindController.expandRegexReplacement(r'$1: $2', match), 'x: 1');
  });

  test('expands full match and escaped dollar placeholders', () {
    final match = RegExp(r'\w+').firstMatch('total')!;

    expect(FindController.expandRegexReplacement(r'$$$&', match), r'$total');
  });

  test('expands named regex replacement groups', () {
    final match = RegExp(r'(?<name>[a-z]+)=(?<value>\d+)').firstMatch('x=1')!;

    expect(
      FindController.expandRegexReplacement(r'${name}: ${value}', match),
      'x: 1',
    );
  });
}
