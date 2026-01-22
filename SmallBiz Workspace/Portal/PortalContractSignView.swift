//
//  PortalContractSignView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/20/26.
//

import Foundation
import SwiftUI
import UIKit

struct PortalContractSignView: View {
    @Environment(\.dismiss) private var dismiss

    let portal: PortalService
    let session: PortalSession
    let contract: Contract

    // UI
    @State private var signerName: String
    @State private var mode: SignatureMode = .draw
    @State private var typedSignature: String = ""
    @State private var hasConsented: Bool = false

    // Drawing
    @State private var strokes: [[CGPoint]] = [[]]
    @State private var strokeWidth: CGFloat = 3.0

    // Status
    @State private var isSubmitting: Bool = false
    @State private var errorText: String? = nil
    @State private var successText: String? = nil

    enum SignatureMode: String, CaseIterable, Identifiable {
        case draw = "Draw"
        case type = "Type"
        var id: String { rawValue }
    }

    init(portal: PortalService, session: PortalSession, contract: Contract) {
        self.portal = portal
        self.session = session
        self.contract = contract
        _signerName = State(initialValue: contract.client?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contract") {
                    Text(contract.title.isEmpty ? "Untitled Contract" : contract.title)
                    Text("Status: \(contract.statusRaw.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Signer") {
                    TextField("Signer name", text: $signerName)
                        .textInputAutocapitalization(.words)

                    Picker("Signature", selection: $mode) {
                        ForEach(SignatureMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .draw {
                    Section("Draw Signature") {
                        SignaturePad(
                            strokes: $strokes,
                            strokeWidth: strokeWidth
                        )
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.secondary.opacity(0.25))
                        )

                        HStack {
                            Button("Clear") { clearDrawing() }
                            Spacer()
                            Slider(value: $strokeWidth, in: 2...6, step: 1) {
                                Text("Thickness")
                            }
                            .frame(width: 160)
                        }
                    }
                } else {
                    Section("Type Signature") {
                        TextField("Type your signature", text: $typedSignature)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section {
                    Toggle(isOn: $hasConsented) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I agree to sign electronically")
                            Text("This signature is legally binding.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                    }
                }

                if let successText {
                    Section {
                        Text(successText)
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Sign Contract")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting || !canSubmit)
                }
            }
            .navigationTitle("Sign Contract")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        let nameOK = !signerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let consentOK = hasConsented

        switch mode {
        case .draw:
            return nameOK && consentOK && drawingHasInk
        case .type:
            let t = typedSignature.trimmingCharacters(in: .whitespacesAndNewlines)
            return nameOK && consentOK && !t.isEmpty
        }
    }

    private var drawingHasInk: Bool {
        // If any stroke has more than 1 point, we consider it "inked"
        return strokes.contains(where: { $0.count > 1 })
    }

    private func clearDrawing() {
        strokes = [[]]
        errorText = nil
        successText = nil
    }

    private func submit() {
        errorText = nil
        successText = nil

        // Guard status: only "sent" can sign (you chose A)
        let currentStatus = ContractStatus(rawValue: contract.statusRaw) ?? .draft
        guard currentStatus == .sent else {
            errorText = "This contract must be marked as Sent before it can be signed."
            return
        }

        guard hasConsented else {
            errorText = "Consent is required to sign."
            return
        }

        let cleanName = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            errorText = "Signer name is required."
            return
        }

        isSubmitting = true

        do {
            switch mode {
            case .draw:
                let png = SignatureRenderer.pngData(
                    strokes: strokes,
                    size: CGSize(width: 1200, height: 420),
                    strokeWidth: strokeWidth
                )

                try portal.signContractFromPortal(
                    contractID: contract.id,
                    session: session,
                    signerName: cleanName,
                    signatureType: .drawn,
                    signatureImageData: png,
                    signatureText: nil,
                    consentVersion: "portal-consent-v1",
                    deviceLabel: session.deviceLabel
                )

            case .type:
                let t = typedSignature.trimmingCharacters(in: .whitespacesAndNewlines)
                try portal.signContractFromPortal(
                    contractID: contract.id,
                    session: session,
                    signerName: cleanName,
                    signatureType: .typed,
                    signatureImageData: nil,
                    signatureText: t,
                    consentVersion: "portal-consent-v1",
                    deviceLabel: session.deviceLabel
                )
            }

            successText = "Signed successfully."
            // Optional: auto-close after signing
            // dismiss()

        } catch {
            errorText = error.localizedDescription
        }

        isSubmitting = false
    }
}

// MARK: - Signature Pad (SwiftUI)
private struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    var strokeWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.secondarySystemBackground)

                Path { path in
                    for stroke in strokes {
                        guard let first = stroke.first else { continue }
                        path.move(to: first)
                        for p in stroke.dropFirst() {
                            path.addLine(to: p)
                        }
                    }
                }
                .stroke(.primary, lineWidth: strokeWidth)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = value.location
                        if strokes.isEmpty { strokes = [[]] }

                        // Start a new stroke if last one is empty and we just began
                        if strokes[strokes.count - 1].isEmpty {
                            strokes[strokes.count - 1].append(p)
                        } else {
                            strokes[strokes.count - 1].append(p)
                        }
                    }
                    .onEnded { _ in
                        // Start next stroke
                        strokes.append([])
                    }
            )
        }
    }
}

// MARK: - Rendering to PNG
private enum SignatureRenderer {
    static func pngData(strokes: [[CGPoint]], size: CGSize, strokeWidth: CGFloat) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // predictable output
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { ctx in
            // white background
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let path = UIBezierPath()
            path.lineWidth = strokeWidth * 3 // scale up for PDF niceness
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            for stroke in strokes {
                guard let first = stroke.first else { continue }
                path.move(to: scaled(first, from: strokesBounds(strokes: strokes), to: size))
                for p in stroke.dropFirst() {
                    path.addLine(to: scaled(p, from: strokesBounds(strokes: strokes), to: size))
                }
            }

            UIColor.black.setStroke()
            path.stroke()
        }

        return img.pngData()
    }

    private static func strokesBounds(strokes: [[CGPoint]]) -> CGRect {
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0

        for stroke in strokes {
            for p in stroke {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
        }

        if minX == .greatestFiniteMagnitude {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let w = max(1, maxX - minX)
        let h = max(1, maxY - minY)
        return CGRect(x: minX, y: minY, width: w, height: h)
    }

    private static func scaled(_ p: CGPoint, from bounds: CGRect, to size: CGSize) -> CGPoint {
        // Add margin so it doesn't slam edges
        let margin: CGFloat = 40
        let target = CGRect(x: margin, y: margin, width: size.width - 2*margin, height: size.height - 2*margin)

        let nx = (p.x - bounds.minX) / bounds.width
        let ny = (p.y - bounds.minY) / bounds.height

        return CGPoint(
            x: target.minX + nx * target.width,
            y: target.minY + ny * target.height
        )
    }
}
