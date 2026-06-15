import WidgetKit
import AppIntents

@main
struct PRVIOControlsBundle: ControlWidgetBundle {
    var body: some ControlWidget {
        AddTaskControl()
        OpenChatControl()
        ShoppingControl()
        ScanControl()
    }
}
