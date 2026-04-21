import UIKit
import ObjectiveC

private nonisolated(unsafe) var frameBlasterStateKey: UInt8 = 0

private enum FrameAssetFormat: String, CaseIterable {
    case png
    case jpg
    case jpeg
    case heic
    case webp
}

private struct PerformanceFrameSource {
    let data: Data
    let scale: CGFloat
}

@MainActor
private final class PerformanceDisplayLinkTarget: NSObject {
    weak var imageView: UIImageView?

    @objc func step(_ displayLink: CADisplayLink) {
        imageView?.stepPerformanceAnimation(displayLink)
    }
}

@MainActor
private final class FrameBlasterAnimationState {
    var performanceFrameSources: [PerformanceFrameSource] = []
    var displayLink: CADisplayLink?
    let displayLinkTarget = PerformanceDisplayLinkTarget()
    var frameDuration: CFTimeInterval = 0
    var elapsedTime: CFTimeInterval = 0
    var currentFrameNumber: Int = 0
    var remainingRepeats: Int = 0
    var repeatsForever = false
    var completion: (() -> Void)?
    var completionWorkItem: DispatchWorkItem?

    func resetPlaybackState() {
        elapsedTime = 0
        currentFrameNumber = 0
    }
}

@MainActor
private func animationFrameName(animationName: String, index: Int, numberPadding padding: Int) -> String {
    "\(animationName)\(String(format: "%0\(padding)d", index))"
}

@MainActor
private func loadAssetCatalogFrames(named animationName: String,
                                    range: Range<Int>,
                                    numberPadding padding: Int,
                                    from bundle: Bundle = .main) -> [UIImage] {
    range.compactMap { index in
        UIImage(
            named: animationFrameName(animationName: animationName, index: index, numberPadding: padding),
            in: bundle,
            compatibleWith: nil
        )
    }
}

@MainActor
private func loadPerformanceFrameSources(named animationName: String,
                                         range: Range<Int>,
                                         numberPadding padding: Int,
                                         from bundle: Bundle = .main) -> [PerformanceFrameSource] {
    range.compactMap { index in
        makePerformanceFrameSource(
            named: animationFrameName(animationName: animationName, index: index, numberPadding: padding),
            bundle: bundle
        )
    }
}

@MainActor
private func makePerformanceFrameSource(named resourceName: String, bundle: Bundle) -> PerformanceFrameSource? {
    let screenScale = UIScreen.main.scale
    let scaleSuffix: String?

    if screenScale >= 3 {
        scaleSuffix = "@3x"
    } else if screenScale >= 2 {
        scaleSuffix = "@2x"
    } else {
        scaleSuffix = nil
    }

    let candidateNames = [scaleSuffix.map { resourceName + $0 }, resourceName].compactMap { $0 }

    for candidateName in candidateNames {
        for format in FrameAssetFormat.allCases {
            guard let url = bundle.url(forResource: candidateName, withExtension: format.rawValue),
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                continue
            }

            let imageScale = candidateName == resourceName ? 1 : screenScale
            return PerformanceFrameSource(data: data, scale: imageScale)
        }
    }

    return nil
}

@MainActor
private func makeImage(from source: PerformanceFrameSource) -> UIImage? {
    UIImage(data: source.data, scale: source.scale)
}

@MainActor
public extension UIImageView {
    /// The currently displayed frame index for FrameBlaster's performance animation path.
    var frameBlasterCurrentFrameNumber: Int {
        frameBlasterState.currentFrameNumber
    }

    /// The currently displayed image for either animation path.
    var frameBlasterCurrentFrameImage: UIImage? {
        image
    }

    @available(*, deprecated, renamed: "frameBlasterCurrentFrameNumber")
    var currentFrameNumber: Int {
        frameBlasterCurrentFrameNumber
    }

    @available(*, deprecated, renamed: "frameBlasterCurrentFrameImage")
    var currentFrameImage: UIImage? {
        frameBlasterCurrentFrameImage
    }

    /// Creates an image view that uses `UIImageView.animationImages` with asset-catalog frames.
    convenience init(frame: CGRect,
                     assetCatalogAnimationNamed animationName: String,
                     range: Range<Int>,
                     numberPadding padding: Int,
                     fps: Int,
                     repeat repeatCount: Int,
                     bundle: Bundle = .main,
                     completion completionBlock: (() -> Void)? = nil) {
        self.init(frame: frame)
        playAssetCatalogAnimation(
            animationName,
            range: range,
            numberPadding: padding,
            fps: fps,
            repeat: repeatCount,
            bundle: bundle,
            completion: completionBlock
        )
    }

    /// Creates an image view sized from its first asset-catalog frame and starts standard playback.
    convenience init(assetCatalogAnimationNamed animationName: String,
                     range: Range<Int>,
                     numberPadding padding: Int,
                     fps: Int,
                     repeat repeatCount: Int,
                     bundle: Bundle = .main,
                     completion completionBlock: (() -> Void)? = nil) {
        let frames = loadAssetCatalogFrames(named: animationName, range: range, numberPadding: padding, from: bundle)
        self.init(image: frames.first)
        configureAssetCatalogAnimation(
            with: frames,
            fps: fps,
            repeatCount: repeatCount,
            completion: completionBlock
        )
    }

    /// Convenience only: loads frames named like `frame0001` from the asset catalog and uses UIKit's standard animation engine.
    func playAssetCatalogAnimation(_ animationName: String,
                                   range: Range<Int>,
                                   numberPadding padding: Int,
                                   fps: Int,
                                   repeat repeatCount: Int,
                                   bundle: Bundle = .main,
                                   completion completionBlock: (() -> Void)? = nil) {
        stopFrameBlasterPerformanceAnimation()
        stopAnimating()
        cancelAssetCatalogCompletion()

        let frames = loadAssetCatalogFrames(named: animationName, range: range, numberPadding: padding, from: bundle)
        configureAssetCatalogAnimation(
            with: frames,
            fps: fps,
            repeatCount: repeatCount,
            completion: completionBlock
        )
    }

    /// Creates an image view that streams file-backed frames as compressed data for lower peak memory use.
    convenience init(frame: CGRect,
                     performanceAnimationNamed animationName: String,
                     range: Range<Int>,
                     numberPadding padding: Int,
                     fps: Int,
                     repeat repeatCount: Int,
                     bundle: Bundle = .main,
                     completion completionBlock: (() -> Void)? = nil) {
        self.init(frame: frame)
        playPerformanceAnimation(
            animationName,
            range: range,
            numberPadding: padding,
            fps: fps,
            repeat: repeatCount,
            bundle: bundle,
            completion: completionBlock
        )
    }

    /// Creates an image view sized from its first file-backed frame and starts performance playback.
    convenience init(performanceAnimationNamed animationName: String,
                     range: Range<Int>,
                     numberPadding padding: Int,
                     fps: Int,
                     repeat repeatCount: Int,
                     bundle: Bundle = .main,
                     completion completionBlock: (() -> Void)? = nil) {
        let frameSources = loadPerformanceFrameSources(
            named: animationName,
            range: range,
            numberPadding: padding,
            from: bundle
        )
        self.init(image: frameSources.first.flatMap(makeImage))
        configurePerformanceAnimation(
            with: frameSources,
            fps: fps,
            repeatCount: repeatCount,
            completion: completionBlock
        )
    }

    /// Performance path: uses the same `frame0001` naming convenience, but loads compressed files from the bundle on demand.
    func playPerformanceAnimation(_ animationName: String,
                                  range: Range<Int>,
                                  numberPadding padding: Int,
                                  fps: Int,
                                  repeat repeatCount: Int,
                                  bundle: Bundle = .main,
                                  completion completionBlock: (() -> Void)? = nil) {
        stopAnimating()
        cancelAssetCatalogCompletion()

        let frameSources = loadPerformanceFrameSources(
            named: animationName,
            range: range,
            numberPadding: padding,
            from: bundle
        )

        configurePerformanceAnimation(
            with: frameSources,
            fps: fps,
            repeatCount: repeatCount,
            completion: completionBlock
        )
    }

    @available(*, deprecated, renamed: "init(performanceAnimationNamed:range:numberPadding:fps:repeat:completion:)")
    convenience init(animationNamed animationName: String,
                     range: Range<Int>,
                     numberPadding padding: Int,
                     fps: Int,
                     repeat repeatCount: Int,
                     completion completionBlock: (() -> Void)? = nil) {
        self.init(
            performanceAnimationNamed: animationName,
            range: range,
            numberPadding: padding,
            fps: fps,
            repeat: repeatCount,
            completion: completionBlock
        )
    }

    @available(*, deprecated, renamed: "init(frame:performanceAnimationNamed:range:numberPadding:fps:repeat:completion:)")
    convenience init(frame: CGRect,
                     animationNamed animationName: String,
                     range: Range<Int>,
                     numberPadding padding: Int,
                     fps: Int,
                     repeat repeatCount: Int,
                     completion completionBlock: (() -> Void)? = nil) {
        self.init(
            frame: frame,
            performanceAnimationNamed: animationName,
            range: range,
            numberPadding: padding,
            fps: fps,
            repeat: repeatCount,
            completion: completionBlock
        )
    }

    @available(*, deprecated, renamed: "playPerformanceAnimation(_:range:numberPadding:fps:repeat:completion:)")
    func playAnimation(_ animationName: String,
                       range: Range<Int>,
                       numberPadding padding: Int,
                       fps: Int,
                       repeat repeatCount: Int,
                       completion completionBlock: (() -> Void)? = nil) {
        playPerformanceAnimation(
            animationName,
            range: range,
            numberPadding: padding,
            fps: fps,
            repeat: repeatCount,
            completion: completionBlock
        )
    }

    /// Stops only the FrameBlaster performance animation path. Use `stopAnimating()` for asset-catalog animations.
    func stopFrameBlasterPerformanceAnimation() {
        guard frameBlasterState.displayLink != nil else {
            frameBlasterState.completion = nil
            return
        }

        stopPerformanceAnimation(invokeCompletion: false, clearFrameSources: true)
    }

    var isFrameBlasterPerformanceAnimating: Bool {
        frameBlasterState.displayLink != nil
    }

    /// Stops either FrameBlaster animation path and cancels any completion scheduled by these helpers.
    func stopFrameBlasterAnimation() {
        cancelAssetCatalogCompletion()
        stopFrameBlasterPerformanceAnimation()
        stopAnimating()
        animationImages = nil
    }

    private func configureAssetCatalogAnimation(with frames: [UIImage],
                                                fps: Int,
                                                repeatCount: Int,
                                                completion: (() -> Void)?) {
        guard !frames.isEmpty else {
            animationImages = nil
            image = nil
            return
        }

        let safeFPS = max(fps, 1)
        animationImages = frames
        animationDuration = Double(frames.count) / Double(safeFPS)
        animationRepeatCount = repeatCount
        image = frames.first

        startAnimating()
        scheduleAssetCatalogCompletionIfNeeded(
            frameCount: frames.count,
            fps: safeFPS,
            repeatCount: repeatCount,
            completion: completion
        )
    }

    private func configurePerformanceAnimation(with frameSources: [PerformanceFrameSource],
                                               fps: Int,
                                               repeatCount: Int,
                                               completion: (() -> Void)?) {
        stopPerformanceAnimation(invokeCompletion: false, clearFrameSources: true)

        guard !frameSources.isEmpty else {
            image = nil
            return
        }

        let safeFPS = max(fps, 1)
        let state = frameBlasterState
        state.performanceFrameSources = frameSources
        state.frameDuration = 1.0 / Double(safeFPS)
        state.remainingRepeats = max(repeatCount, 0)
        state.repeatsForever = repeatCount == 0
        state.completion = completion
        state.resetPlaybackState()

        image = frameSources.first.flatMap(makeImage)
        startPerformanceAnimation()
    }

    private func startPerformanceAnimation() {
        let state = frameBlasterState
        guard !state.performanceFrameSources.isEmpty, state.displayLink == nil else {
            return
        }

        state.displayLinkTarget.imageView = self

        let displayLink = CADisplayLink(target: state.displayLinkTarget, selector: #selector(PerformanceDisplayLinkTarget.step(_:)))
        displayLink.add(to: .main, forMode: .default)
        state.displayLink = displayLink
    }

    private func stopPerformanceAnimation(invokeCompletion: Bool, clearFrameSources: Bool) {
        let state = frameBlasterState
        let completion = invokeCompletion ? state.completion : nil

        state.displayLink?.invalidate()
        state.displayLink = nil
        state.displayLinkTarget.imageView = nil
        state.elapsedTime = 0

        if clearFrameSources {
            state.performanceFrameSources = []
        }

        state.completion = nil
        completion?()
    }

    private func scheduleAssetCatalogCompletionIfNeeded(frameCount: Int,
                                                        fps: Int,
                                                        repeatCount: Int,
                                                        completion: (() -> Void)?) {
        guard repeatCount != 0, let completion else {
            return
        }

        let totalDuration = (Double(frameCount) / Double(fps)) * Double(repeatCount)
        let workItem = DispatchWorkItem { [weak self] in
            self?.frameBlasterState.completionWorkItem = nil
            completion()
        }

        frameBlasterState.completionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration, execute: workItem)
    }

    private func cancelAssetCatalogCompletion() {
        frameBlasterState.completionWorkItem?.cancel()
        frameBlasterState.completionWorkItem = nil
    }

    private var frameBlasterState: FrameBlasterAnimationState {
        if let state = objc_getAssociatedObject(self, &frameBlasterStateKey) as? FrameBlasterAnimationState {
            return state
        }

        let state = FrameBlasterAnimationState()
        objc_setAssociatedObject(self, &frameBlasterStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }
}

@MainActor
private extension UIImageView {
    func stepPerformanceAnimation(_ displayLink: CADisplayLink) {
        let state = frameBlasterState
        guard !state.performanceFrameSources.isEmpty else {
            stopPerformanceAnimation(invokeCompletion: false, clearFrameSources: true)
            return
        }

        state.elapsedTime += displayLink.targetTimestamp - displayLink.timestamp

        while state.elapsedTime >= state.frameDuration {
            state.elapsedTime -= state.frameDuration

            let nextFrameNumber = state.currentFrameNumber + 1
            if nextFrameNumber < state.performanceFrameSources.count {
                state.currentFrameNumber = nextFrameNumber
                image = makeImage(from: state.performanceFrameSources[nextFrameNumber])
                continue
            }

            image = makeImage(from: state.performanceFrameSources[state.performanceFrameSources.count - 1])

            if state.repeatsForever {
                state.currentFrameNumber = 0
                image = makeImage(from: state.performanceFrameSources[0])
                continue
            }

            if state.remainingRepeats > 1 {
                state.remainingRepeats -= 1
                state.currentFrameNumber = 0
                image = makeImage(from: state.performanceFrameSources[0])
                continue
            }

            stopPerformanceAnimation(invokeCompletion: true, clearFrameSources: true)
            return
        }
    }
}
