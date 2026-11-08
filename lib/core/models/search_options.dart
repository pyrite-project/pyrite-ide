import 'package:flutter/foundation.dart';

/// One of a search field's `Aa` / `ab` / `.*` toggles.
enum SearchOption {
  caseSensitive('Aa'),
  wholeWord('ab'),
  regex('.*');

  const SearchOption(this.label);

  /// The glyph the toggle button shows.
  final String label;
}

/// The VS Code style match options behind a search field's `Aa` / `ab` / `.*`
/// toggles.
@immutable
class SearchOptions {
  const SearchOptions({
    this.caseSensitive = false,
    this.wholeWord = false,
    this.regex = false,
  });

  final bool caseSensitive;
  final bool wholeWord;
  final bool regex;

  bool isOn(SearchOption option) => switch (option) {
    SearchOption.caseSensitive => caseSensitive,
    SearchOption.wholeWord => wholeWord,
    SearchOption.regex => regex,
  };

  SearchOptions toggled(SearchOption option) => switch (option) {
    SearchOption.caseSensitive => copyWith(caseSensitive: !caseSensitive),
    SearchOption.wholeWord => copyWith(wholeWord: !wholeWord),
    SearchOption.regex => copyWith(regex: !regex),
  };

  /// Compiles [query] under these options, or returns null for an empty
  /// query. Throws [FormatException] when [regex] is on and [query] is not a
  /// valid regular expression.
  RegExp? patternFor(String query) {
    if (query.isEmpty) return null;
    var source = regex ? query : RegExp.escape(query);
    if (wholeWord) source = '\\b(?:$source)\\b';
    return RegExp(source, caseSensitive: caseSensitive);
  }

  SearchOptions copyWith({bool? caseSensitive, bool? wholeWord, bool? regex}) {
    return SearchOptions(
      caseSensitive: caseSensitive ?? this.caseSensitive,
      wholeWord: wholeWord ?? this.wholeWord,
      regex: regex ?? this.regex,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchOptions &&
      other.caseSensitive == caseSensitive &&
      other.wholeWord == wholeWord &&
      other.regex == regex;

  @override
  int get hashCode => Object.hash(caseSensitive, wholeWord, regex);
}
