import SwiftUI
import WidgetKit

@main
struct MochiWidgetBundle: WidgetBundle {
    var body: some Widget {
        PetStatusWidget()
        MochiLiveActivity()
    }
}
