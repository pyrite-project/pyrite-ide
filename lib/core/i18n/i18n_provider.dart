import 'package:flutter/widgets.dart';
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
  // Service-layer translations are snapshots. Watching here makes any state
  // provider that translates a label depend on the entire data registry, so a
  // theme contribution would dispose and recreate unrelated editor/terminal
  // state. Widgets use translateForWidget below and remain reactive.
  final locale = ref.read(activeLocaleProvider);
  final registry = ref.read(dataRegistryProvider);
  return translateFromRegistry(registry, locale, key);
}

String translateWithReplacements(
  Ref ref,
  I18nKey key, [
  Map<String, String> replacements = const {},
]) {
  final locale = ref.read(activeLocaleProvider);
  final registry = ref.read(dataRegistryProvider);
  return translateWithReplacementsFromRegistry(
    registry,
    locale,
    key,
    replacements,
  );
}

/// The container-scoped form of [translateWithReplacements], for widgets that
/// only have a [BuildContext] and reach the registry through the container.
String translateWithReplacementsFromRegistry(
  DataRegistry registry,
  String locale,
  I18nKey key, [
  Map<String, String> replacements = const {},
]) {
  var value = translateFromRegistry(registry, locale, key);
  for (final entry in replacements.entries) {
    value = value.replaceAll('{${entry.key}}', entry.value);
  }
  return value;
}

String translateForWidget(WidgetRef ref, I18nKey key) {
  final locale = ref.watch(activeLocaleProvider);
  final registry = ref.watch(dataRegistryProvider);
  return translateFromRegistry(registry, locale, key);
}

/// The widget form of [translateWithReplacements].
///
/// [translateWithReplacements] takes a provider `Ref`; a widget only has a
/// `WidgetRef`, and they are unrelated types.
String translateForWidgetWithReplacements(
  WidgetRef ref,
  I18nKey key, [
  Map<String, String> replacements = const {},
]) {
  final locale = ref.watch(activeLocaleProvider);
  final registry = ref.watch(dataRegistryProvider);
  return translateWithReplacementsFromRegistry(
    registry,
    locale,
    key,
    replacements,
  );
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

/// Translates [key] with optional `{placeholder}` replacements.
///
/// Services that cannot watch providers accept this as an injected hook so
/// their status text follows the active locale; the default
/// [fallbackTranslate] keeps them usable without a data registry (tests,
/// pure functions).
typedef I18nTranslate =
    String Function(I18nKey key, [Map<String, String> replacements]);

String fallbackTranslate(
  I18nKey key, [
  Map<String, String> replacements = const {},
]) {
  var value = key.fallback;
  for (final entry in replacements.entries) {
    value = value.replaceAll('{${entry.key}}', entry.value);
  }
  return value;
}

/// Binds [translateWithReplacements] to [ref], ready to inject into services.
I18nTranslate translateFor(Ref ref) {
  return (key, [replacements = const {}]) =>
      translateWithReplacements(ref, key, replacements);
}

/// Builds an [I18nTranslate] from plain locale-pack snapshots.
///
/// [translateFor] 返回的闭包捕获 [Ref]，持有它的服务实例会经由 ref 连到整个
/// ProviderContainer；一旦服务把自身（或捕获 this 的闭包）作为 isolate 消息
/// 发送，就会报 "object is unsendable"。此工厂只捕获纯数据的文本表，随实例
/// 跨 isolate 是安全的；调用方需在 locale 或注册表变化时重建服务以刷新快照。
I18nTranslate translateFromLocaleSnapshot({
  required Map<String, Map<String, String>> packs,
  required String locale,
}) {
  return (key, [replacements = const {}]) {
    var value =
        packs[locale]?[key.key] ??
        packs[defaultLocale]?[key.key] ??
        key.fallback;
    for (final entry in replacements.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  };
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

/// Translates [key] from a plain [BuildContext].
///
/// For `State` widgets that are not `ConsumerState`: they have a context but no
/// `WidgetRef`. Reaching the container this way — instead of converting the
/// widget — keeps a pure text change from altering a widget's type.
String translateInContext(BuildContext context, I18nKey key) {
  final container = ProviderScope.containerOf(context, listen: false);
  return translateFromRegistry(
    container.read(dataRegistryProvider),
    container.read(activeLocaleProvider),
    key,
  );
}

/// [translateInContext] with `{placeholder}` values.
String translateInContextWithReplacements(
  BuildContext context,
  I18nKey key, [
  Map<String, String> replacements = const {},
]) {
  final container = ProviderScope.containerOf(context, listen: false);
  return translateWithReplacementsFromRegistry(
    container.read(dataRegistryProvider),
    container.read(activeLocaleProvider),
    key,
    replacements,
  );
}
