import 'package:code_forge/code_forge/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/i18n/i18n_provider.dart';
import 'package:tabbed_view/tabbed_view.dart';

final Map<String, CodeForgeController> expansionControllerMap = {};

final StateProvider<TabbedViewController> expansionViewController =
    StateProvider<TabbedViewController>((ref) {
      final tabText = translate(ref, I18nKey.expansionWelcomeTab);
      final contentText = translate(ref, I18nKey.expansionWelcomeContent);
      return TabbedViewController([
        TabData(
          closable: false,
          value: {"type": "page", "id": "welcome"},
          text: tabText,
          content: Center(child: Text(contentText)),
          leading: (context, status) => Padding(
            padding: EdgeInsetsGeometry.directional(
              start: 5,
              end: 10,
              top: 5,
              bottom: 5,
            ),
            child: Image.asset(
              "assets/icons/app_icon.webp",
              width: 15,
              height: 15,
            ),
          ),
        ),
      ]);
    });
