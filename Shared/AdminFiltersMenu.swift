import SwiftUI

/// Top-right Filters menu used across admin list screens. Single-select only.
struct AdminFiltersMenu<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option?
    var allowsClear: Bool = true
    var clearTitle: String = "admin.filters.clear".localized
    var clearSystemImage: String = "xmark.circle"
    let title: (Option) -> String
    let systemImage: (Option) -> String

    private var isFilterActive: Bool { selection != nil }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Label(
                        title(option),
                        systemImage: selection == option ? "checkmark" : systemImage(option)
                    )
                }
            }

            if allowsClear {
                Divider()
                Button {
                    selection = nil
                } label: {
                    Label(
                        clearTitle,
                        systemImage: isFilterActive ? clearSystemImage : "checkmark"
                    )
                }
            }
        } label: {
            Label(
                "admin.filters".localized,
                systemImage: isFilterActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
        }
    }
}
