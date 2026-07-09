import 'package:rfw/rfw.dart' as rfw;
import 'package:pyrite_ide/pages/plugins/widgets/markdown.dart';
import 'package:pyrite_ide/pages/plugins/widgets/button.dart';
import 'package:pyrite_ide/pages/plugins/widgets/text_field.dart';
import 'package:pyrite_ide/pages/plugins/widgets/selection.dart';

rfw.LocalWidgetLibrary createPyriteMaterialWidgets() {
  return rfw.LocalWidgetLibrary(<String, rfw.LocalWidgetBuilder>{
    ...rfw.createMaterialWidgets().widgets,
    'Markdown': buildMarkdown,
    'MarkdownWidget': buildMarkdown,
    'MarkdownBlock': buildMarkdownBlock,
    'TextField': buildTextField,
    'FilledButton': buildFilledButton,
    "Checkbox": buildCheckbox,
    "Switch": buildSwitch,
    "RadioGroup": buildRadioGroup,
    "Slider": buildSlider,
  });
}
