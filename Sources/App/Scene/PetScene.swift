import SpriteKit
import UIKit

/// Renders Mochi and translates touches into intent.
///
/// Deliberately dumb: the scene knows how to animate a state and how to detect a
/// tap versus a long press. It does not know what a stat is, cannot mutate the
/// pet, and holds no business rules — it reports events upwards and is redrawn
/// from `PetStore`.
final class PetScene: SKScene {

    /// Fired when the player taps the creature.
    var onTap: (() -> Void)?
    /// Fired on a sustained press.
    var onLongPress: (() -> Void)?

    private static let frameSize: CGFloat = 32
    private let spriteScale: CGFloat = 7

    private var petNode: SKSpriteNode?
    private var shadowNode: SKSpriteNode?
    private var currentStage: GrowthStage = .hatchling
    private var currentState: BehaviorState = .idle
    private var textureCache: [String: [SKTexture]] = [:]
    private var isTouching = false
    private var didFireLongPress = false
    private var spawnedAmbient = false

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        buildShadow()
        buildPet()
        spawnAmbientMotes()
        // Keeping the scene paused when nothing changes is the cheapest way to
        // honour "低功耗动画策略": no frames are rendered while the creature is
        // idle-asleep and the app is in the background.
        view.preferredFramesPerSecond = 30
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutNodes()
    }

    // MARK: - Public API

    func update(stage: GrowthStage, state: BehaviorState) {
        if stage != currentStage {
            currentStage = stage
            buildPet()
        }
        guard state != currentState || petNode?.action(forKey: "anim") == nil else { return }
        currentState = state
        play(state)
    }

    /// Small burst used when something good happens (feeding, levelling up).
    func celebrateBurst(color: UIColor = .systemPink) {
        burst(colors: [color, .systemYellow, .white], count: 10)
    }

    // MARK: - Nodes

    private func buildShadow() {
        shadowNode?.removeFromParent()
        let texture = Self.radialShadowTexture(diameter: 96)
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: spriteScale * 16, height: spriteScale * 4)
        node.alpha = 0.28
        node.zPosition = 1
        addChild(node)
        shadowNode = node
        layoutNodes()
    }

    private func buildPet() {
        petNode?.removeFromParent()

        let node = SKSpriteNode()
        node.size = CGSize(
            width: Self.frameSize * spriteScale * CGFloat(currentStage.renderScale),
            height: Self.frameSize * spriteScale * CGFloat(currentStage.renderScale)
        )
        node.zPosition = 3
        node.texture?.filteringMode = .nearest
        addChild(node)
        petNode = node
        layoutNodes()
        play(currentState)
    }

    private func layoutNodes() {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.46)
        petNode?.position = center
        shadowNode?.position = CGPoint(x: center.x, y: center.y - (Self.frameSize * spriteScale * CGFloat(currentStage.renderScale)) / 2 + 10)
    }

    // MARK: - Animation

    private func textures(for state: BehaviorState) -> [SKTexture] {
        let key = "\(currentStage.spritePrefix)_\(state.rawValue)"
        if let cached = textureCache[key] { return cached }

        let strip = SKTexture(imageNamed: key)
        strip.filteringMode = .nearest
        let count = state.frameCount
        // `imageNamed` returns a 1x1 placeholder texture when the asset is
        // missing; slicing that would divide by zero in spirit, so bail out and
        // let the node keep its previous frame.
        guard strip.size().width > 0, strip.size().height > 0 else { return [] }

        var frames: [SKTexture] = []
        for index in 0..<count {
            let rect = CGRect(
                x: CGFloat(index) / CGFloat(count),
                y: 0,
                width: 1.0 / CGFloat(count),
                height: 1.0
            )
            let frame = SKTexture(rect: rect, in: strip)
            frame.filteringMode = .nearest
            frames.append(frame)
        }
        textureCache[key] = frames
        return frames
    }

    private func play(_ state: BehaviorState) {
        guard let petNode else { return }
        let frames = textures(for: state)
        guard !frames.isEmpty else { return }

        petNode.removeAction(forKey: "anim")
        let animate = SKAction.animate(
            with: frames,
            timePerFrame: state.secondsPerFrame,
            resize: true,
            restore: false
        )

        if state.loops {
            petNode.run(.repeatForever(animate), withKey: "anim")
        } else {
            // One-shots hand control back to the store, which decides what the
            // creature settles into. The scene never guesses.
            petNode.run(animate, withKey: "anim")
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        isTouching = true
        didFireLongPress = false

        // Immediate feedback so the surface feels alive even before the model
        // round-trips.
        squash()

        let point = touch.location(in: self)
        guard let petNode, petNode.frame.contains(point) else { return }

        run(.sequence([
            .wait(forDuration: 0.55),
            .run { [weak self] in
                guard let self, self.isTouching, !self.didFireLongPress else { return }
                self.didFireLongPress = true
                self.burst(colors: [.white, .systemPink], count: 6)
                self.onLongPress?()
            }
        ]), withKey: "longpress")
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        removeAction(forKey: "longpress")
        guard !didFireLongPress else { return }
        onTap?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
        removeAction(forKey: "longpress")
    }

    // MARK: - Effects

    private func squash() {
        guard let petNode else { return }
        let squash = SKAction.sequence([
            .scaleY(to: 0.9, duration: 0.06),
            .scaleY(to: 1.0, duration: 0.10)
        ])
        petNode.run(squash, withKey: "squash")
    }

    private func burst(colors: [UIColor], count: Int) {
        guard let petNode else { return }
        for i in 0..<count {
            let size = CGFloat.random(in: 3...6)
            let particle = SKSpriteNode(color: colors[i % colors.count], size: CGSize(width: size, height: size))
            particle.position = petNode.position
            particle.zPosition = 6
            addChild(particle)

            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 30...80)
            let destination = CGPoint(
                x: petNode.position.x + CGFloat(cos(angle)) * distance,
                y: petNode.position.y + CGFloat(sin(angle)) * distance
            )

            particle.run(.sequence([
                .group([
                    .move(to: destination, duration: 0.45),
                    .fadeOut(withDuration: 0.45),
                    .scale(to: 0.4, duration: 0.45)
                ]),
                .removeFromParent()
            ]))
        }
    }

    private func spawnAmbientMotes() {
        guard !spawnedAmbient else { return }
        spawnedAmbient = true

        let emit = SKAction.run { [weak self] in
            guard let self else { return }
            let mote = SKSpriteNode(color: .white.withAlphaComponent(0.5), size: CGSize(width: 2, height: 2))
            mote.position = CGPoint(
                x: CGFloat.random(in: 0...max(1, self.size.width)),
                y: -6
            )
            mote.zPosition = 2
            mote.alpha = CGFloat.random(in: 0.15...0.45)
            self.addChild(mote)
            let rise = CGFloat.random(in: 40...90)
            mote.run(.sequence([
                .group([
                    .moveBy(x: CGFloat.random(in: -10...10), y: rise, duration: 5.5),
                    .fadeOut(withDuration: 5.5)
                ]),
                .removeFromParent()
            ]))
        }

        run(.repeatForever(.sequence([.wait(forDuration: 0.9), emit])), withKey: "motes")
    }

    private static func radialShadowTexture(diameter: CGFloat) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter / 2))
        let image = renderer.image { context in
            let bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter / 2)
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                startRadius: 0,
                endCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                endRadius: bounds.width / 2,
                options: []
            )
            _ = context
        }
        return SKTexture(image: image)
    }
}
