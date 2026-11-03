import ClipBridgeKit
import UIKit

/// 键盘的整个界面：顶部状态行，中间卡片列表（或一条说明文字），底部一排按键。纯 UIKit，没有图片资源。
final class KeyboardView: UIView {
    var onCardTap: ((ClipItem) -> Void)?
    var onRefresh: (() -> Void)?
    var onSend: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onSpace: (() -> Void)?

    let globeButton = KeyboardView.makeKey(symbol: "globe", label: "下一个键盘")
    let statusLabel = UILabel()

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let scrollView = UIScrollView()
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
        scrollView.isHidden = false
        for view in cardStack.arrangedSubviews {
            cardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for item in items {
            let card = ClipCardButton(item: item)
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

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 1
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        spinner.hidesWhenStopped = true

        let statusRow = UIStackView(arrangedSubviews: [statusLabel, spinner])
        statusRow.axis = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .center

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

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.isHidden = true

        let center = UIView()
        center.translatesAutoresizingMaskIntoConstraints = false
        for subview in [scrollView, messageLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            center.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: center.topAnchor),
                subview.bottomAnchor.constraint(equalTo: center.bottomAnchor),
                subview.leadingAnchor.constraint(equalTo: center.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: center.trailingAnchor),
            ])
        }

        refreshButton.addAction(UIAction { [weak self] _ in self?.onRefresh?() }, for: .touchUpInside)
        sendButton.addAction(UIAction { [weak self] _ in self?.onSend?() }, for: .touchUpInside)
        backspaceButton.addAction(UIAction { [weak self] _ in self?.onBackspace?() }, for: .touchUpInside)
        spaceButton.addAction(UIAction { [weak self] _ in self?.onSpace?() }, for: .touchUpInside)

        let bar = UIStackView(arrangedSubviews: [globeButton, refreshButton, spaceButton, sendButton, backspaceButton])
        bar.axis = .horizontal
        bar.spacing = 6
        bar.distribution = .fill
        for key in [globeButton, refreshButton, backspaceButton] {
            key.widthAnchor.constraint(equalToConstant: 48).isActive = true
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
                attributes.font = UIFont.preferredFont(forTextStyle: .subheadline)
                return attributes
            }
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = label
        return button
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
        return formatter
    }()

    init(item: ClipItem) {
        self.item = item
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .button

        previewLabel.font = .preferredFont(forTextStyle: .subheadline)
        previewLabel.textColor = .label
        previewLabel.numberOfLines = 3
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.text = Self.preview(of: item.content)

        metaLabel.font = .preferredFont(forTextStyle: .caption2)
        metaLabel.textColor = .secondaryLabel
        let source = item.source == .pc ? "电脑" : "手机"
        let when = Self.relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date())
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
