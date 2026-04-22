//
//  UpdateBannerView.swift
//  Demolish
//
//  Banner that slides up from the bottom when a new version is available.
//

import SwiftUI

struct UpdateBannerView: View {
    @ObservedObject var updateChecker: AppUpdateChecker
    @State private var isUpdateButtonHovered = false
    @State private var isDismissButtonHovered = false

    var body: some View {
        HStack(spacing: 16) {
            statusIcon

            statusText
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            if case .failed = updateChecker.state {
                retryButton
            }

            if case .available = updateChecker.state {
                updateButton
            }

            if case .downloading(let progress) = updateChecker.state {
                downloadProgress(progress)
            }

            if case .installing = updateChecker.state {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }

            if canDismiss {
                dismissButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(bannerBackground)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Subviews

    @ViewBuilder
    private var statusIcon: some View {
        switch updateChecker.state {
        case .available:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.blue)
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 20))
                .foregroundColor(.blue.opacity(0.8))
        case .installing:
            Image(systemName: "gear")
                .font(.system(size: 20))
                .foregroundColor(.orange)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(.yellow)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch updateChecker.state {
        case .available(let version, _):
            Text("Demolish v\(version) is available")
        case .downloading:
            Text("Downloading update\u{2026}")
        case .installing:
            Text("Installing update\u{2026}")
        case .failed(let message):
            Text(message)
                .lineLimit(1)
        default:
            EmptyView()
        }
    }

    private var updateButton: some View {
        Button(action: { updateChecker.downloadAndInstall() }) {
            Text("Update & Restart")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isUpdateButtonHovered ? Color.blue.opacity(0.9) : Color.blue.opacity(0.75))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isUpdateButtonHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
                NSCursor.arrow.set()
            }
        }
    }

    private var retryButton: some View {
        Button(action: { updateChecker.checkForUpdate() }) {
            Text("Retry")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop(); NSCursor.arrow.set() }
        }
    }

    private func downloadProgress(_ progress: Double) -> some View {
        HStack(spacing: 10) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 120)
                .tint(.blue)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var canDismiss: Bool {
        switch updateChecker.state {
        case .available, .failed:
            return true
        default:
            return false
        }
    }

    private var dismissButton: some View {
        Button(action: { updateChecker.dismiss() }) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(isDismissButtonHovered ? 0.9 : 0.5))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isDismissButtonHovered ? 0.15 : 0.05))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isDismissButtonHovered = hovering
            }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop(); NSCursor.arrow.set() }
        }
    }

    private var bannerBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: -4)
    }
}
