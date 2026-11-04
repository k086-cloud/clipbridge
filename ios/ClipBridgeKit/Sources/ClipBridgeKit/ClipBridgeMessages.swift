import Foundation

// 三个 target 共用的中文错误文案。`error.localizedDescription` 直接可用。

extension ClipBridgeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "token 不对，电脑拒绝了请求（401）"
        case .notFound:
            return "这个地址上不是 ClipBridge 服务（404）"
        case .serverOutdated:
            return "电脑上的 ClipBridge 服务版本太旧，不支持这个操作（405）"
        case let .payloadTooLarge(detail):
            return detail.isEmpty ? "内容太大，电脑拒收（413）" : "内容太大，电脑拒收（413）：\(detail)"
        case let .unprocessable(detail):
            return detail.isEmpty ? "请求参数不合法（422）" : "请求参数不合法（422）：\(detail)"
        case let .clipboardUnavailable(detail):
            return detail.isEmpty ? "电脑写剪贴板失败（503）" : "电脑写剪贴板失败（503）：\(detail)"
        case let .unexpectedStatus(code):
            return "电脑返回了意外的状态码 \(code)"
        case .contentEmpty:
            return "没有可发送的内容"
        case let .contentTooLarge(bytes, limit):
            return "内容 \(bytes) 字节，超过上限 \(limit) 字节"
        case .invalidURL:
            return "配对地址无效"
        case .invalidResponse:
            return "对方的回应不是 ClipBridge 服务的格式"
        case let .transport(code):
            switch code {
            case .notConnectedToInternet:
                return "iPhone 拒绝了本地网络访问，或者没有连 Wi-Fi"
            case .appTransportSecurityRequiresSecureConnection:
                return "系统拦截了明文 HTTP（ATS 未放行）"
            case .timedOut:
                return "连接超时，电脑没有回应"
            case .cannotConnectToHost:
                return "连不上电脑的这个端口（服务没开或防火墙拦了）"
            case .cannotFindHost, .dnsLookupFailed:
                return "找不到这个主机名"
            case .networkConnectionLost:
                return "网络连接中断"
            default:
                return "网络错误（\(code.rawValue)）"
            }
        case let .underlying(domain, code):
            if domain == NSPOSIXErrorDomain, code == Int(EPERM) {
                return "当前进程没有联网权限（键盘需要开启「允许完全访问」）"
            }
            return "网络错误（\(domain) \(code)）"
        }
    }
}

extension KeychainError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain 里没有 token（或本扩展没有访问权限）"
        case .interactionNotAllowed:
            return "设备还没有首次解锁，Keychain 暂时不可读"
        case .missingEntitlement:
            return "Keychain 访问组和签名不匹配（工程配置错误）"
        case .notAvailable:
            return "Keychain 不可用（键盘没开「允许完全访问」时会这样）"
        case .duplicateItem:
            return "Keychain 条目重复"
        case .unexpectedData:
            return "Keychain 里的 token 格式不对"
        case let .status(code):
            return "Keychain 错误（\(code)）"
        }
    }
}

extension PairingURLError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAURL:
            return "不是一个链接"
        case let .wrongScheme(scheme):
            return "不是 clipbridge:// 开头的配对链接（现在是 \(scheme ?? "没有协议头")）"
        case let .wrongAction(action):
            return "不是配对链接（clipbridge://\(action ?? "")）"
        case .missingHost:
            return "配对链接里缺少 host"
        case let .invalidHost(host):
            return "host 不合法：\(host)"
        case .missingPort:
            return "配对链接里缺少端口"
        case let .invalidPort(port):
            return "端口不合法：\(port)（应为 1–65535）"
        case .missingToken:
            return "配对链接里缺少 token"
        }
    }
}
