import SwiftUI
import UIKit

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = UIView()
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
