import Foundation
import LumaValidation

let core = ValidationSuite.runCore()
let imports = await ValidationSuite.runImports()
let checks = core + imports
for result in checks {
    print("\(result.passed ? "PASS" : "FAIL")  \(result.name)\(result.detail.isEmpty ? "" : " — " + result.detail.replacingOccurrences(of: "\n", with: " / "))")
}
print("\n\(checks.filter(\.passed).count)/\(checks.count) checks passed.")
if checks.contains(where: { !$0.passed }) { exit(1) }
