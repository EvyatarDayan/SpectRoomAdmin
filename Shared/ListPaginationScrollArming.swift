import SwiftUI

/// Which way the user must drag to unlock list pagination.
enum ListPaginationScrollDirection {
    /// Standard lists: finger moves up to reveal more rows at the bottom.
    case towardBottom
    /// Chat threads: finger moves down to reveal older messages at the top.
    case towardTop
}

/// Arms pagination only after the user scrolls toward more content.
/// Pulling the opposite way (e.g. rubber-banding / pull-down on a normal list) disarms it.
struct ListPaginationScrollArming: ViewModifier {
    @Binding var isArmed: Bool
    var direction: ListPaginationScrollDirection
    var minimumDistance: CGFloat = 8
    var armThreshold: CGFloat = 12

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: minimumDistance)
                .onChanged { value in
                    let translation = value.translation.height
                    switch direction {
                    case .towardBottom:
                        if translation < -armThreshold {
                            isArmed = true
                        } else if translation > armThreshold {
                            isArmed = false
                        }
                    case .towardTop:
                        if translation > armThreshold {
                            isArmed = true
                        } else if translation < -armThreshold {
                            isArmed = false
                        }
                    }
                }
        )
    }
}

extension View {
    /// Track whether the user is scrolling toward more paginated content.
    func listPaginationScrollArming(
        isArmed: Binding<Bool>,
        direction: ListPaginationScrollDirection = .towardBottom
    ) -> some View {
        modifier(ListPaginationScrollArming(isArmed: isArmed, direction: direction))
    }
}
