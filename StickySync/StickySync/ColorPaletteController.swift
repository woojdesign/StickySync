import AppKit
import NotesKit

/// The little grid of color chips shown in the on-note color popover.
final class ColorPaletteController: NSViewController {
    var onSelect: ((String) -> Void)?

    private let selectedToken: String

    init(selected: String) {
        self.selectedToken = selected
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let chips = Palette.colors
        let columns = 4
        let chip: CGFloat = 26
        let gap: CGFloat = 8
        let pad: CGFloat = 12
        let rows = Int(ceil(Double(chips.count) / Double(columns)))
        let width = pad * 2 + CGFloat(columns) * chip + CGFloat(columns - 1) * gap
        let height = pad * 2 + CGFloat(rows) * chip + CGFloat(rows - 1) * gap

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        for (i, color) in chips.enumerated() {
            let row = i / columns
            let col = i % columns
            let x = pad + CGFloat(col) * (chip + gap)
            let y = height - pad - chip - CGFloat(row) * (chip + gap)

            let button = NSButton(frame: NSRect(x: x, y: y, width: chip, height: chip))
            button.title = ""
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = chip / 2
            button.layer?.backgroundColor = Appearance.background(for: color.token).cgColor
            let selected = color.token == selectedToken
            button.layer?.borderWidth = selected ? 2.5 : 0.5
            button.layer?.borderColor = (selected ? NSColor.woojClay : NSColor.woojLine)
                .usingColorSpace(.sRGB)?.cgColor
            button.toolTip = color.displayName
            button.tag = i
            button.target = self
            button.action = #selector(pick(_:))
            container.addSubview(button)
        }

        self.view = container
    }

    @objc private func pick(_ sender: NSButton) {
        onSelect?(Palette.colors[sender.tag].token)
    }
}
