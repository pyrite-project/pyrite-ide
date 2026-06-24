import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();
final StateProvider<String> page = StateProvider((ref) => "home");
final StateProvider<String?> selectedPluginId = StateProvider((ref) => null);
