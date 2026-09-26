import 'package:path/path.dart' as path;
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/python.dart';
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
}

/// Python, the language this editor exists for, and the fallback whenever the
/// extension is unknown.
///
/// Not `const`: `Mode` instances from `re_highlight` are built at load time, so
/// neither they nor anything holding them can be a compile-time constant.
final EditorLanguage editorLanguagePython = EditorLanguage(
  langPython,
  'python',
);

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
