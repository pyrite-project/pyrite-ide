import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/board_file_backend.dart';
import 'package:pyrite_ide/core/services/file/serial_board_file_backend.dart';

final boardFileBackendProvider = Provider<BoardFileBackend>(
  (ref) => SerialBoardFileBackend(ref),
);
