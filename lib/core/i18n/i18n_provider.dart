import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pyrite_ide/core/i18n/i18n_key.dart';
import 'package:pyrite_ide/core/services/data_registry.dart';

const defaultLocale = 'zh-CN';

final activeLocaleProvider = StateProvider<String>((ref) => defaultLocale);

final availableLocalesProvider = Provider<List<String>>((ref) {
  final registry = ref.watch(dataRegistryProvider);
  final locales = <String>{defaultLocale, ...registry.availableLocales};
  final sorted = locales.toList()..sort();
  sorted.remove(defaultLocale);
  return [defaultLocale, ...sorted];
});

String translate(Ref ref, I18nKey key) {
  final locale = ref.watch(activeLocaleProvider);
  final registry = ref.watch(dataRegistryProvider);
  return translateFromRegistry(registry, locale, key);
}

String translateForWidget(WidgetRef ref, I18nKey key) {
  final locale = ref.watch(activeLocaleProvider);
  final registry = ref.watch(dataRegistryProvider);
  return translateFromRegistry(registry, locale, key);
}

String translateFromRegistry(
  DataRegistry registry,
  String locale,
  I18nKey key,
) {
  return _lookup(registry, locale, key.key) ??
      _lookup(registry, defaultLocale, key.key) ??
      key.fallback;
}

String resolveI18nText(WidgetRef ref, Object value) {
  if (value is I18nKey) {
    return translateForWidget(ref, value);
  }
  return value.toString();
}

String? _lookup(DataRegistry registry, String locale, String key) {
  final value = registry.getLocale(locale)?[key];
  return value?.toString();
}
