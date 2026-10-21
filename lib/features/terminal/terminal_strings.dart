/// Text for the terminal surfaces added in this change.
///
/// These live here instead of `lib/core/i18n/i18n_key.dart` because that file
/// is outside this module's write scope and is being edited concurrently. Each
/// entry is written as the key the string should eventually carry, so moving
/// them into [I18nKey] is a mechanical copy and the Chinese fallback is already
/// the value that key would hold.
library;

const terminalSearchHint = '搜索终端输出（Ctrl/Cmd+F）';
const terminalSearchPrevious = '上一个匹配项';
const terminalSearchNext = '下一个匹配项';
const terminalSearchCaseSensitive = '区分大小写';
const terminalSearchClose = '关闭搜索';
const terminalSearchNoResults = '无结果';

const terminalUrlCopied = '已复制链接到剪贴板';
const terminalUrlRejected = '不支持打开该链接';
const terminalUrlOpenFailed = '无法打开链接，已复制到剪贴板';
const terminalFileNotFound = '找不到链接指向的文件：{path}';
