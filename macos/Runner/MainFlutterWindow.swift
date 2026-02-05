import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Must match the height used by `UseTitleBar` in Flutter.
  private let flutterHeaderHeight: CGFloat = 45
  private var trafficLightObserverTokens: [NSObjectProtocol] = []

  deinit {
    for token in trafficLightObserverTokens {
      NotificationCenter.default.removeObserver(token)
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    setupTrafficLightCentering()
  }

  private func setupTrafficLightCentering() {
    let center: (Notification.Name) -> Void = { [weak self] name in
      guard let self else { return }
      let token = NotificationCenter.default.addObserver(
        forName: name,
        object: self,
        queue: OperationQueue.main
      ) { [weak self] _ in
        self?.centerTrafficLightsInFlutterHeader()
      }
      self.trafficLightObserverTokens.append(token)
    }

    center(NSWindow.didResizeNotification)
    center(NSWindow.didEndLiveResizeNotification)
    center(NSWindow.didMoveNotification)
    center(NSWindow.didEnterFullScreenNotification)
    center(NSWindow.didExitFullScreenNotification)

    DispatchQueue.main.async { [weak self] in
      self?.centerTrafficLightsInFlutterHeader()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.centerTrafficLightsInFlutterHeader()
    }
  }

  private func centerTrafficLightsInFlutterHeader() {
    guard
      let contentView,
      let closeButton = standardWindowButton(.closeButton),
      let minimizeButton = standardWindowButton(.miniaturizeButton),
      let zoomButton = standardWindowButton(.zoomButton),
      let buttonSuperview = closeButton.superview
    else {
      return
    }

    let targetCenterYInContent = contentView.bounds.height - (flutterHeaderHeight / 2)
    let targetPointInWindow = contentView.convert(
      NSPoint(x: 0, y: targetCenterYInContent),
      to: nil
    )
    let targetPointInSuperview = buttonSuperview.convert(targetPointInWindow, from: nil)

    for button in [closeButton, minimizeButton, zoomButton] {
      var frame = button.frame
      frame.origin.y = targetPointInSuperview.y - (frame.height / 2)

      let minY: CGFloat = 0
      let maxY: CGFloat = max(0, buttonSuperview.bounds.height - frame.height)
      frame.origin.y = max(minY, min(frame.origin.y, maxY))

      button.setFrameOrigin(frame.origin)
    }
  }
}
