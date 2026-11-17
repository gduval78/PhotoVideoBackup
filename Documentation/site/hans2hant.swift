// Character-level Simplified -> Traditional with ICU ("Hans-Hant"). Used by hant_convert.py after its Taiwan vocabulary pass.
import Foundation
let a = CommandLine.arguments
let inp = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[1]))) as! [String]
let t = StringTransform(rawValue: "Hans-Hant")
let out = inp.map { $0.applyingTransform(t, reverse: false) ?? $0 }
try! JSONSerialization.data(withJSONObject: out).write(to: URL(fileURLWithPath: a[2]))
