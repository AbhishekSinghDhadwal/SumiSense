import SwiftUI

enum SumiMotion {
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.84)
    static let gentleSpring = Animation.spring(response: 0.72, dampingFraction: 0.9)
    static let fadeSlide = AnyTransition.move(edge: .bottom).combined(with: .opacity)
}
