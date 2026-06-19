import AppKit
import NotesKit

/// The on-note font picker: a short curated list (each previewed in its own
/// typeface) plus a size stepper. This is the "fonts shouldn't be buried in
/// Format ▸ Font ▸ Show Fonts" feature.
final class FontPickerController: NSViewController {
    var onSelectFont: ((String) -> Void)?
    var onSetSize: ((Double) -> Void)?

    private let selectedFontID: String
    private var size: Double
    private let sizeLabel = NSTextField(labelWithString: "")

    init(selectedFontID: String, size: Double) {
        self.selectedFontID = selectedFontID
        self.size = size
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let width: CGFloat = 184
        let rowH: CGFloat = 30
        let sizeRowH: CGFloat = 40
        let pad: CGFloat = 8
        let options = FontCatalog.options
        let height = pad * 2 + CGFloat(options.count) * rowH + sizeRowH

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        for (i, option) in options.enumerated() {
            let y = height - pad - rowH - CGFloat(i) * rowH
            let button = NSButton(frame: NSRect(x: pad, y: y, width: width - pad * 2, height: rowH))
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.setButtonType(.momentaryChange)
            button.alignment = .left
            button.font = Appearance.font(for: option, size: 15)
            button.title = option.displayName
            button.contentTintColor = .labelColor
            if option.id == selectedFontID {
                button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected")
                button.imagePosition = .imageTrailing
            }
            button.tag = i
            button.target = self
            button.action = #selector(pickFont(_:))
            container.addSubview(button)
        }

        let rowY: CGFloat = pad - 2
        let minus = NSButton(frame: NSRect(x: pad, y: rowY, width: 28, height: 28))
        styleStepper(minus, symbol: "minus", action: #selector(decrease))
        let plus = NSButton(frame: NSRect(x: width - pad - 28, y: rowY, width: 28, height: 28))
        styleStepper(plus, symbol: "plus", action: #selector(increase))

        sizeLabel.frame = NSRect(x: 40, y: rowY, width: width - 80, height: 28)
        sizeLabel.alignment = .center
        sizeLabel.font = .systemFont(ofSize: 12)
        sizeLabel.textColor = .secondaryLabelColor
        updateSizeLabel()

        container.addSubview(minus)
        container.addSubview(plus)
        container.addSubview(sizeLabel)

        self.view = container
    }

    private func styleStepper(_ b: NSButton, symbol: String, action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.imagePosition = .imageOnly
        b.bezelStyle = .roundRect
        b.target = self
        b.action = action
    }

    private func updateSizeLabel() {
        sizeLabel.stringValue = "Size \(Int(size)) pt"
    }

    @objc private func pickFont(_ sender: NSButton) {
        onSelectFont?(FontCatalog.options[sender.tag].id)
    }

    @objc private func decrease() {
        size = FontCatalog.clampSize(size - 1)
        updateSizeLabel()
        onSetSize?(size)
    }

    @objc private func increase() {
        size = FontCatalog.clampSize(size + 1)
        updateSizeLabel()
        onSetSize?(size)
    }
}
