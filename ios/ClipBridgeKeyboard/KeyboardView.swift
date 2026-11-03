import ClipBridgeKit
import UIKit

/// 键盘的整个界面：顶部状态行（固定 20 pt），中间卡片列表（或一条说明文字，唯一可伸缩的一行），底部一排按键（44 pt）。
/// 纯 UIKit，没有图片资源。
final class KeyboardView: UIView {
    var onCardTap: ((ClipItem) -> Void)?
    var onRefresh: (() -> Void)?
    var onSend: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onSpace: (() -> Void)?

    let globeButton = KeyboardView.makeKey(symbol: "globe", label: "下一个键盘")
    let statusLabel = UILabel()

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let scrollView = CardScrollView()
    private let cardStack = UIStackView()
    private let messageLabel = UILabel()
    private let backspaceButton = KeyboardView.makeKey(symbol: "delete.left", label: "删除")
    private let spaceButton = KeyboardView.makeKey(symbol: nil, label: "空格")
    private let refreshButton = KeyboardView.makeKey(symbol: "arrow.clockwise", label: "刷新")
    private let sendButton = KeyboardView.makeKey(symbol: "paperplane", label: "发送剪贴板", showsLabel: true)

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    // MARK: - 状态切换

    func setLoading(_ loading: Bool) {
        if loading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    func setSending(_ sending: Bool) {
        sendButton.isEnabled = !sending
        sendButton.alpha = sending ? 0.5 : 1
    }

    func show(items: [ClipItem]) {
        messageLabel.isHidden = true
        messageLabel.text = nil
        scrollView.isHidden = false
        for view in cardStack.arrangedSubviews {
            cardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let now = Date()
        for item in items {
            let card = ClipCardButton(item: item, now: now)
            card.addAction(UIAction { [weak self, weak card] _ in
                guard let item = card?.item else { return }
                self?.onCardTap?(item)
            }, for: .touchUpInside)
            cardStack.addArrangedSubview(card)
        }
        scrollView.setContentOffset(.zero, animated: false)
    }

    func showMessage(_ text: String) {
        for view in cardStack.arrangedSubviews {
            cardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        scrollView.isHidden = true
        messageLabel.isHidden = false
        messageLabel.text = text
    }

    // MARK: - 布局

    private func build() {
        backgroundColor = .systemGroupedBackground

        statusLabel.font = Self.scaledFont(.caption1, base: 12, max: 18)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 1
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        spinner.hidesWhenStopped = true

        let statusRow = UIStackView(arrangedSubviews: [statusLabel, spinner])
        statusRow.axis = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .center
        // 固定高度：否则这一行会吃掉所有多余高度，卡片区域被压成 0 pt（无头布局实测）。
        statusRow.heightAnchor.constraint(equalToConstant: 20).isActive = true

        cardStack.axis = .vertical
        cardStack.spacing = 6
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(cardStack)
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .none
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            cardStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            cardStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        messageLabel.font = Self.scaledFont(.subheadline, base: 15, max: 21)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.isHidden = true

        // 中间这块是唯一可伸缩的一行：滚动视图铺满；说明文字只居中，不决定高度。
        let center = UIView()
        center.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        center.addSubview(scrollView)
        center.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: center.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: center.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: center.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: center.trailingAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: center.centerYAnchor),
            messageLabel.topAnchor.constraint(greaterThanOrEqualTo: center.topAnchor),
            messageLabel.bottomAnchor.constraint(lessThanOrEqualTo: center.bottomAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: center.leadingAnchor, constant: 8),
            messageLabel.trailingAnchor.constraint(equalTo: center.trailingAnchor, constant: -8),
        ])

        refreshButton.addAction(UIAction { [weak self] _ in self?.onRefresh?() }, for: .touchUpInside)
        sendButton.addAction(UIAction { [weak self] _ in self?.onSend?() }, for: .touchUpInside)
        backspaceButton.addAction(UIAction { [weak self] _ in self?.onBackspace?() }, for: .touchUpInside)
        spaceButton.addAction(UIAction { [weak self] _ in self?.onSpace?() }, for: .touchUpInside)

        let bar = UIStackView(arrangedSubviews: [globeButton, refreshButton, spaceButton, sendButton, backspaceButton])
        bar.axis = .horizontal
        bar.spacing = 6
        bar.distribution = .fill
        for key in [globeButton, refreshButton, backspaceButton] {
            // 999 而不是 required：地球键隐藏时 UIStackView 会给它加一条 required 的 width == 0，必须让这条让路。
            let width = key.widthAnchor.constraint(equalToConstant: 48)
            width.priority = UILayoutPriority(999)
            width.isActive = true
        }
        spaceButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sendButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spaceButton.widthAnchor.constraint(equalTo: sendButton.widthAnchor).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let root = UIStackView(arrangedSubviews: [statusRow, center, bar])
        root.axis = .vertical
        root.spacing = 6
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            root.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    /// 跟随动态字体但封顶：键盘高度和按键高度是固定的，字再大就放不下了。
    static func scaledFont(_ style: UIFont.TextStyle, base: CGFloat, max: CGFloat) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: base), maximumPointSize: max)
    }

    private static func makeKey(symbol: String?, label: String, showsLabel: Bool = false) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .secondarySystemGroupedBackground
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        configuration.imagePadding = 6
        if let symbol {
            configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        }
        if showsLabel || symbol == nil {
            configuration.title = label
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = KeyboardView.scaledFont(.subheadline, base: 15, max: 21)
                return attributes
            }
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = label
        return button
    }
}

/// 卡片是 UIControl，而 UIScrollView 默认不打断 UIControl 的触摸：按住卡片超过 150 ms 再拖，列表就滚不动。
/// 允许滚动开始时取消卡片的触摸；delaysContentTouches 保持默认，点按仍会高亮。
private final class CardScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }
}

/// 一张卡片：内容预览（最多 3 行）+ 来源和时间。整张可点。
final class ClipCardButton: UIControl {
    let item: ClipItem

    private let previewLabel = UILabel()
    private let metaLabel = UILabel()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter
    }()

    init(item: ClipItem, now: Date) {
        self.item = item
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .button

        previewLabel.font = KeyboardView.scaledFont(.subheadline, base: 15, max: 21)
        previewLabel.textColor = .label
        previewLabel.numberOfLines = 3
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.text = Self.preview(of: item.content)

        metaLabel.font = KeyboardView.scaledFont(.caption2, base: 11, max: 17)
        metaLabel.textColor = .secondaryLabel
        let source = item.source == .pc ? "电脑" : "手机"
        // 时间以手机时钟为准；电脑时钟走快时不显示「N 秒后」，一律当作「现在」。
        let when = Self.relativeFormatter.localizedString(for: min(item.timestamp, now), relativeTo: now)
        metaLabel.text = "\(source) · \(when) · \(item.content.count) 字符"
        accessibilityLabel = "\(metaLabel.text ?? "")，\(previewLabel.text ?? "")"

        let stack = UIStackView(arrangedSubviews: [previewLabel, metaLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? .tertiarySystemFill : .secondarySystemGroupedBackground
        }
    }

    /// 预览只取前 200 个字符，换行折成「↵」，避免 100 KB 的文本进 UILabel。
    static func preview(of content: String, limit: Int = 200) -> String {
        let head = content.prefix(limit)
        let flattened = head
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .trimmingCharacters(in: .whitespaces)
        return content.count > limit ? flattened + "…" : flattened
    }
}
