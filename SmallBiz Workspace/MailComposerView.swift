//
//  MailComposerView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/12/26.
//

import Foundation
import SwiftUI
import MessageUI

struct MailComposerView: UIViewControllerRepresentable {
    typealias UIViewControllerType = MFMailComposeViewController

    let subject: String
    let body: String
    let attachmentData: Data
    let attachmentMimeType: String
    let attachmentFileName: String

    @Environment(\.dismiss) private var dismiss

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerView
        init(_ parent: MailComposerView) { self.parent = parent }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            parent.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.addAttachmentData(attachmentData, mimeType: attachmentMimeType, fileName: attachmentFileName)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}
