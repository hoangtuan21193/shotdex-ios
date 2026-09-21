import Foundation
import Testing
@testable import ShotDex
@testable import ShotDexKit

/// The grading chain: what a node is, and the rules that make a chain
/// behave like Resolve's serial nodes rather than like a list of settings.
struct ColorNodeChainTests {
    private func recipe(nodes: [ColorNode]) -> VideoProjectRecipe {
        var recipe = VideoProjectRecipe(clips: [])
        recipe.nodes = nodes
        return recipe
    }

    private var lifted: ColorNode {
        var node = ColorNode()
        node.adjustments[.exposure] = 0.4
        return node
    }

    // MARK: What a node is

    @Test func afreshNodeChangesNothing() {
        #expect(ColorNode().isIdentity)
        #expect(!lifted.isIdentity)
    }

    /// Adding an empty node must be free — otherwise splitting a grade into
    /// readable pieces costs a render pass per piece.
    @Test func aChainOfEmptyNodesIsNoGrade() {
        #expect(!recipe(nodes: [ColorNode(), ColorNode(), ColorNode()]).hasGrade)
        #expect(recipe(nodes: [ColorNode(), lifted]).hasGrade)
    }

    /// A bypassed node is still in the chain and still does nothing.
    @Test func aBypassedNodeIsNotWork() {
        var off = lifted
        off.isEnabled = false
        #expect(!recipe(nodes: [off]).hasGrade)
        #expect(recipe(nodes: [off]).nodes.count == 1)
    }

    @Test func anUnnamedNodeIsCalledByItsPosition() {
        #expect(ColorNode().displayName(at: 0) == "Node 1")
        #expect(ColorNode().displayName(at: 3) == "Node 4")
        #expect(ColorNode(name: "Skin").displayName(at: 3) == "Skin")
    }

    // MARK: Lookup

    @Test func aMissingSelectionFallsBackToTheFirstNode() {
        let first = ColorNode(name: "First")
        let chain = recipe(nodes: [first, ColorNode(name: "Second")])
        #expect(chain.node(nil).id == first.id)
        #expect(chain.node(UUID()).id == first.id)
        #expect(chain.nodeIndex(UUID()) == 0)
    }

    @Test func aNodeKnowsWhereItIsInTheChain() {
        let a = ColorNode(), b = ColorNode(), c = ColorNode()
        let chain = recipe(nodes: [a, b, c])
        #expect(chain.nodeIndex(c.id) == 2)
        #expect(chain.node(b.id).id == b.id)
    }

    // MARK: Windows belong to their node

    @Test func aWindowLivesOnTheNodeItLimits() {
        var first = ColorNode()
        first.masks = [PhotoMask(name: "Face", component: PhotoMaskComponent(kind: .radialGradient))]
        let chain = recipe(nodes: [first, ColorNode()])
        #expect(chain.nodes[0].masks.count == 1)
        #expect(chain.nodes[1].masks.isEmpty)
        // And a node carrying only a window is still work: the window is
        // what makes the node's adjustments local.
        #expect(chain.hasGrade)
    }

    /// An untracked window comes back untouched — the whole array pass has
    /// to be a no-op or every frame pays for a feature nobody used.
    @Test func anUntrackedWindowIsNotMoved() {
        var node = ColorNode()
        let mask = PhotoMask(name: "Face", component: PhotoMaskComponent(kind: .radialGradient))
        node.masks = [mask]
        #expect(node.trackedMasks(at: 3.5) == [mask])
        #expect(node.track(for: mask.id) == nil)
    }
}
