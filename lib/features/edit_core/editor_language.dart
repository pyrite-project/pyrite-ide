import 'package:path/path.dart' as path;
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/python.dart' show langPython;
import 'package:re_highlight/languages/shell.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

/// Grammar chosen for a file path, together with the id used to label it.
///
/// [Mode] instances are reused across editors on purpose: `SyntaxHighlighter`
/// keys its internal grammar cache on the language's hash code and registers
/// the mode with the `Highlight` instance, so handing out the same constant
/// avoids re-registering a grammar per tab.
class EditorLanguage {
  const EditorLanguage(this.mode, this.id);

  final Mode mode;
  final String id;

  /// The language's line comment marker, or null when a line-comment toggle
  /// makes no sense for the grammar (XML/HTML/Markdown comment with paired
  /// block delimiters and JSON has no comments at all).
  String? get lineCommentMarker => switch (id) {
    'python' || 'ini' || 'properties' || 'yaml' || 'shell' => '#',
    'c' || 'cpp' || 'javascript' => '//',
    'lua' => '--',
    _ => null,
  };

  /// The paired delimiters a block comment toggle wraps with, or null when the
  /// grammar has none.
  ///
  /// Null is not a "fall back to line comments" case: JSON has no comments at
  /// all, and guessing a delimiter there would corrupt the file. The caller is
  /// expected to leave the buffer untouched instead.
  ///
  /// Python's is `"""` rather than the C-style `/* */` because a MicroPython
  /// file is nearly always Python and `"""` reads as the comment the user
  /// expected rather than a syntax error to a reader who never ran it.
  ({String start, String end})? get blockCommentDelimiters => switch (id) {
    'python' => (start: '"""', end: '"""'),
    'c' || 'cpp' || 'javascript' => (start: '/*', end: '*/'),
    'xml' || 'markdown' => (start: '<!--', end: '-->'),
    _ => null,
  };
}

/// Hardware peripheral classes, highlighted through the `type` scope.
const List<String> _pythonPeripheralClasses = [
  'Accel', 'ADC', 'ADCBlock', 'APA102', 'BLE', 'CAN', 'DAC', 'DHT',
  'DHT11', 'DHT22', 'DS18X20', 'FrameBuffer', 'I2C', 'I2S', 'LED',
  'NeoPixel', 'OneWire', 'Pin', 'PWM', 'RTC', 'SDCard', 'Servo', 'Signal',
  'SoftI2C', 'SoftSPI', 'SPI', 'Switch', 'Timer', 'TouchPad', 'UART',
  'WDT', 'WLAN',
];

/// Python — the language this editor exists for — and the fallback whenever
/// the extension is unknown.
///
/// Built on the original `langPython` grammar in place, with the keyword
/// classes its stock list lacks: peripheral classes as `type`, and
/// `self`/`cls` as `variable.language` (the stock grammar matches `self` with
/// a bare mode that carries no scope, which no theme can style). The stock
/// `built_in` list already covers everything a sketch can call without
/// importing (`print`, `len`, `str`, ...), and module names stay plain on
/// purpose — a module is imported, not built in, so neither the stock grammar
/// nor any conventional theme colors it. The `Mode` instance is the same
/// shared `langPython` object, so the highlighter's grammar cache and
/// registration behave exactly as before, and nothing outside this file
/// changes.
///
/// Cost profile: re_highlight compiles a language lazily on its first
/// highlight (guarded by `isCompiled`), so tuning the raw grammar here lands
/// before the first compile and costs nothing afterwards; keyword classes
/// compile into a single lookup per language, so the extra words don't change
/// the per-line matching cost, and highlighting already runs line-by-line off
/// the UI thread. Pure Dart — Android behaves identically to the desktop.
///
/// Not `const`: `Mode` instances from `re_highlight` are built at load time, so
/// neither they nor anything holding them can be a compile-time constant.
final EditorLanguage editorLanguagePython = _pythonEditorLanguage();

EditorLanguage _pythonEditorLanguage() {
  final keywords = Map<String, dynamic>.from(
    langPython.keywords as Map<dynamic, dynamic>,
  );
  keywords['variable.language'] = ['self', 'cls'];
  keywords['type'] = _pythonPeripheralClasses;
  langPython.keywords = keywords;

  final contains = langPython.contains;
  if (contains is List) {
    for (final mode in contains.whereType<Mode>()) {
      if (mode.begin == r'\bself\b' && mode.scope == null) {
        mode.scope = 'variable.language';
        break;
      }
    }
  }
  return EditorLanguage(langPython, 'python');
}

/// Grammar for [filePath], chosen from its extension (case-insensitive).
///
/// The editor used to pass `langPython` for every file regardless of what was
/// opened, so a `config.json` or `README.md` was highlighted with Python
/// keywords and strings. Unknown extensions fall back to
/// [editorLanguagePython] rather than plain text, because this is a Python
/// editor and an unrecognised extension is far more likely to be a script
/// variant than prose.
EditorLanguage resolveEditorLanguage(String? filePath) {
  if (filePath == null || filePath.isEmpty) return editorLanguagePython;
  final extension = path.extension(filePath).toLowerCase();
  if (extension.isEmpty) return editorLanguagePython;
  return _byExtension[extension] ?? editorLanguagePython;
}

final Map<String, EditorLanguage> _byExtension = <String, EditorLanguage>{
  // Primary target.
  '.py': editorLanguagePython,
  '.pyw': editorLanguagePython,
  '.pyi': editorLanguagePython,

  // Config and data files that show up in MicroPython projects.
  // re_highlight has no TOML grammar; INI is the closest shape.
  '.toml': EditorLanguage(langIni, 'ini'),
  '.ini': EditorLanguage(langIni, 'ini'),
  '.cfg': EditorLanguage(langIni, 'ini'),
  '.conf': EditorLanguage(langIni, 'ini'),
  '.properties': EditorLanguage(langProperties, 'properties'),
  '.env': EditorLanguage(langProperties, 'properties'),
  '.json': EditorLanguage(langJson, 'json'),
  '.yaml': EditorLanguage(langYaml, 'yaml'),
  '.yml': EditorLanguage(langYaml, 'yaml'),
  '.xml': EditorLanguage(langXml, 'xml'),
  '.html': EditorLanguage(langXml, 'xml'),
  '.htm': EditorLanguage(langXml, 'xml'),
  '.svg': EditorLanguage(langXml, 'xml'),

  // Docs.
  '.md': EditorLanguage(langMarkdown, 'markdown'),
  '.markdown': EditorLanguage(langMarkdown, 'markdown'),

  // Native and scripting code that shows up around an embedded project.
  '.c': EditorLanguage(langC, 'c'),
  '.h': EditorLanguage(langC, 'c'),
  '.cpp': EditorLanguage(langCpp, 'cpp'),
  '.cc': EditorLanguage(langCpp, 'cpp'),
  '.cxx': EditorLanguage(langCpp, 'cpp'),
  '.hpp': EditorLanguage(langCpp, 'cpp'),
  '.sh': EditorLanguage(langShell, 'shell'),
  '.bash': EditorLanguage(langShell, 'shell'),
  '.zsh': EditorLanguage(langShell, 'shell'),
  '.js': EditorLanguage(langJavascript, 'javascript'),
  '.mjs': EditorLanguage(langJavascript, 'javascript'),
  '.lua': EditorLanguage(langLua, 'lua'),
};
