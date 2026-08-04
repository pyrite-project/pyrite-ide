from pyrite_sdk.api.ui.page import Page
from pyrite_sdk.api.ui.widgets import Center, NewWidget, Scaffold, Text
from pyrite_sdk.core.plugin import UiPlugin
from pyrite_sdk.models.consts import Package, Ui


def build_home_page() -> Page:
    page = Page([Package.core.widgets, Package.core.material])
    root = NewWidget(Ui.root).add_to(page)
    Scaffold().add_to(root).add(Center()).add(Text("Minimal legacy plugin"))
    return page


class MinimalLegacyPlugin(UiPlugin):
    def __init__(self) -> None:
        super().__init__()
        self.pages["home"] = build_home_page()

    def on_start(self) -> None:
        print("minimal legacy plugin started")
        self.settings.get(
            "editor.font_size",
            callback=lambda **_: print("minimal legacy plugin SDK call completed"),
        )
        self.bridge.refresh(call_on_refresh=False)

    def on_dispose(self) -> None:
        print("minimal legacy plugin disposed")


plugin = MinimalLegacyPlugin()
plugin.start()
