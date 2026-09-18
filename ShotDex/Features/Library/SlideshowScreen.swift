import Photos
import SwiftUI
import UIKit

/// Full-screen automatic playback of a run of photos, as Photos' Slideshow
/// does: each photo holds for a beat, then cross-fades into the next.
///
/// Deliberately plain. Photos' own slideshow carries themes and music; those
/// belong to Video Studio here, which already composes a real movie from a
/// selection. This is the lightweight "just show them to me" version, so it
/// stays a viewer, not an export.
struct SlideshowScreen: View {
    /// Asset ids in play order.
    let assetIds: [String]
    /// Where to start — normally the photo the viewer was showing.
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    @State private var image: UIImage?
    @State private var isPaused = false
    @State private var areControlsVisible = true
    @State private var advanceTask: Task<Void, Never>?
    @State private var controlsHideTask: Task<Void, Never>?
    @AppStorage(SettingsKeys.slideshowSeconds) private var secondsPerPhoto = 3.0

    /// The range the interval stepper walks, in seconds per photo.
    private static let intervals: [Double] = [2, 3, 5, 8, 12]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
                    .id(index)
                    .transition(.opacity)
            } else {
                ProgressView().tint(.white)
            }

            if areControlsVisible {
                controls
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.6),
            value: index
        )
        .animation(.easeOut(duration: 0.2), value: areControlsVisible)
        .task {
            index = min(max(startIndex, 0), max(0, assetIds.count - 1))
            await loadCurrent()
            scheduleAdvance()
            scheduleControlsHide()
        }
        .onDisappear {
            advanceTask?.cancel()
            controlsHideTask?.cancel()
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassBackground(Circle())
                .accessibilityLabel("Close slideshow")

                Spacer()

                Menu {
                    Picker("Seconds per photo", selection: $secondsPerPhoto) {
                        ForEach(Self.intervals, id: \.self) { value in
                            Text("\(Int(value))s per photo").tag(value)
                        }
                    }
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 52, height: 52)
                }
                .foregroundStyle(.white)
                .glassBackground(Circle())
                .accessibilityLabel("Seconds per photo")
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 12) {
                slideshowButton("backward.end", "Previous photo") { step(by: -1) }
                slideshowButton(isPaused ? "play.fill" : "pause.fill",
                                isPaused ? "Resume" : "Pause") {
                    isPaused.toggle()
                    if isPaused {
                        advanceTask?.cancel()
                    } else {
                        scheduleAdvance()
                    }
                }
                slideshowButton("forward.end", "Next photo") { step(by: 1) }
            }
            .padding(.bottom, 24)

            Text("\(index + 1) of \(assetIds.count)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 16)
        }
    }

    private func slideshowButton(
        _ systemImage: String,
        _ label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glassBackground(Circle())
        .accessibilityLabel(label)
    }

    // MARK: Playback

    private func step(by delta: Int) {
        guard !assetIds.isEmpty else { return }
        advanceTask?.cancel()
        index = (index + delta + assetIds.count) % assetIds.count
        Task {
            await loadCurrent()
            if !isPaused { scheduleAdvance() }
        }
        scheduleControlsHide()
    }

    /// Waits out the hold, then advances. Re-armed after every load rather than
    /// run on a timer, so a slow photo never causes two advances to pile up.
    private func scheduleAdvance() {
        advanceTask?.cancel()
        advanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(secondsPerPhoto))
            guard !Task.isCancelled, !isPaused, !assetIds.isEmpty else { return }
            index = (index + 1) % assetIds.count
            await loadCurrent()
            guard !Task.isCancelled, !isPaused else { return }
            scheduleAdvance()
        }
    }

    private func loadCurrent() async {
        guard assetIds.indices.contains(index),
              let asset = PhotoLibraryService.fetchAssets(ids: [assetIds[index]]).first
        else { return }
        let loaded: UIImage? = await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestDetailImage(
                for: asset,
                targetSize: ActiveDisplay.pixelSize(),
                allowNetwork: true,
                progress: { _ in }
            ) { result, isDegraded in
                // The Bool is PhotoKit's degraded flag, not "is final". Wait
                // for the real rendition: a slideshow holds each photo long
                // enough that the wait costs nothing, and a blurry flash
                // before the sharp frame would be obvious.
                guard !hasResumed, !isDegraded else { return }
                hasResumed = true
                continuation.resume(returning: result)
            }
        }
        if let loaded { image = loaded }
    }

    private func toggleControls() {
        areControlsVisible.toggle()
        if areControlsVisible { scheduleControlsHide() }
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            areControlsVisible = false
        }
    }
}
