import Logging

public enum Loggers {
    public static let api = Logger(label: "com.swiftgh.api")
    public static let auth = Logger(label: "com.swiftgh.auth")
    public static let cmd = Logger(label: "com.swiftgh.cmd")
}
