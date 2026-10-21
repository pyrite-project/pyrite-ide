import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/serial/web_repl_handshake.dart';

void main() {
  group('awaitsWebReplPassword', () {
    test('matches the password prompt at the start of a line', () {
      expect(awaitsWebReplPassword('WebREPL connected\r\nPassword: '), isTrue);
    });

    test('matches a prompt indented by the device', () {
      expect(awaitsWebReplPassword('  Password:'), isTrue);
    });

    test('ignores the word password inside ordinary output', () {
      expect(awaitsWebReplPassword('my password is secret'), isFalse);
      expect(awaitsWebReplPassword('Password reset done'), isFalse);
    });
  });

  group('showsWebReplPrompt', () {
    test('matches a bare prompt at the end of a chunk', () {
      expect(showsWebReplPrompt('>>>'), isTrue);
    });

    test('matches a prompt followed by a space', () {
      expect(showsWebReplPrompt('MicroPython v1.22\r\n>>> '), isTrue);
    });

    test('matches a prompt followed by a newline', () {
      expect(showsWebReplPrompt('>>>\r\n'), isTrue);
    });

    test('ignores an OK echo that is not a prompt', () {
      expect(showsWebReplPrompt('OK'), isFalse);
      expect(showsWebReplPrompt("os.remove('x')\r\n"), isFalse);
    });

    test('ignores the arrow sequence inside text', () {
      expect(showsWebReplPrompt('print(">>>")\n'), isFalse);
    });
  });
}
