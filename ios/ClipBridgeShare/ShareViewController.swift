//
//  ShareViewController.swift
//  ClipBridgeShare
//
//  Created by Charles Chen on 11/2/26.
//

import UIKit
import Social
import ClipBridgeKit

class ShareViewController: SLComposeServiceViewController {

    /// 阶段 4 实现共享扩展时使用；现在先把共享层链接进来，确认三个 target 都能 import。
    private let pairingStore: (any PairingStore)? = SharedPairingStore.live()

    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        return true
    }

    override func didSelectPost() {
        // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
    
        // Inform the host that we're done, so it un-blocks its UI. Note: Alternatively you could call super's -didSelectPost, which will similarly complete the extension context.
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }

}
