import Foundation
import ObjectiveC

/// Opens NSOpenPanel on Mac via the Objective-C runtime.
/// UIDocumentPickerViewController fails on "Designed for iPad" because it relies
/// on an XPC remote view service that is non-functional in that environment.
///
/// runModal returns NSInteger (not an ObjC object) — perform(_:) does not capture
/// integer return values, so we use a typed IMP cast via class_getMethodImplementation.
@MainActor
enum MacOpenPanel {
    static func pickFolder() -> URL? {
        guard ProcessInfo.processInfo.isiOSAppOnMac,
              let cls = NSClassFromString("NSOpenPanel") as? NSObject.Type,
              let panel = cls.value(forKey: "openPanel") as? NSObject
        else { return nil }

        panel.setValue(false, forKey: "canChooseFiles")
        panel.setValue(true,  forKey: "canChooseDirectories")
        panel.setValue(false, forKey: "allowsMultipleSelection")

        typealias RunModalFn = @convention(c) (AnyObject, Selector) -> Int
        let sel = NSSelectorFromString("runModal")
        guard let imp = class_getMethodImplementation(object_getClass(panel), sel) else { return nil }
        let response = unsafeBitCast(imp, to: RunModalFn.self)(panel, sel)
        guard response == 1 else { return nil } // NSModalResponseOK == 1

        if let urls = panel.value(forKey: "URLs") as? [URL], let url = urls.first { return url }
        if let arr = panel.value(forKey: "URLs") as? NSArray, let first = arr.firstObject { return (first as? NSURL) as URL? }
        return nil
    }
}
