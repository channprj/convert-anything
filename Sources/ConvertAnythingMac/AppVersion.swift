import Foundation

public enum AppVersion {
  public static func marketingVersion(in bundle: Bundle = .main) -> String {
    guard
      let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    else {
      return ""
    }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
