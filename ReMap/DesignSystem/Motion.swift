import SwiftUI

/// Motion tokens — one vocabulary for the whole app.
enum Motion {
    /// Taps, toggles, small UI state.
    static let snappy = Animation.snappy(duration: 0.3)
    /// Things being born: cards, nodes, chips.
    static let spawn = Animation.bouncy(duration: 0.45, extraBounce: 0.05)
    /// Layout re-flow: nodes moving to new homes.
    static let flow = Animation.smooth(duration: 0.65)
    /// Arrows drawing themselves.
    static let draw = Animation.easeOut(duration: 0.55)
    /// Gap between items in a staggered entrance.
    static let stagger: Duration = .milliseconds(90)
}

/// Grows out of a point (e.g. a hub splitting into groups). Falls back to a fade under Reduce Motion.
struct GrowFromPoint: Transition {
    var offset: CGSize

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase.isIdentity ? 1 : 0.2)
            .offset(phase.isIdentity ? .zero : offset)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// Rises in with a slight blur — used for coach messages and cards.
struct RiseIn: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(y: phase.isIdentity ? 0 : 14)
            .blur(radius: phase.isIdentity ? 0 : 6)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

extension AnyTransition {
    static var pop: AnyTransition { .scale(scale: 0.7).combined(with: .opacity) }
}

/// A one-shot attention pulse, retriggered whenever `trigger` changes.
struct PulseModifier<Trigger: Equatable>: ViewModifier {
    var trigger: Trigger
    var amount: CGFloat = 1.14

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(amount, duration: 0.16, spring: .snappy)
            SpringKeyframe(0.97, duration: 0.14, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
        }
    }
}

extension View {
    func pulse<T: Equatable>(on trigger: T, amount: CGFloat = 1.14) -> some View {
        modifier(PulseModifier(trigger: trigger, amount: amount))
    }
}
