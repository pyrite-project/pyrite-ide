import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/services/file/file_provider.dart';

final ProviderListenable<Directory?> localWorkspaceProvider = fileProvider;
