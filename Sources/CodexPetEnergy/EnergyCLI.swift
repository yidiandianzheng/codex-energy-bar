import Foundation

struct EnergyCLIRequest: Codable {
    let command: String
    var value: String?
    var x: Double?
    var y: Double?

    static func parse(_ args: [String]) throws -> Self {
        guard let command = args.first else { throw CLIError.message("缺少命令，请使用 --cli help") }
        switch command {
        case "status", "hide", "refresh", "snapshot":
            guard args.count == 1 else { throw CLIError.message("该命令不接受额外参数") }
            return Self(command: command)
        case "show":
            guard args.count == 2, ["compact", "quota", "balance", "projects", "radar"].contains(args[1]) else {
                throw CLIError.message("用法：show compact|quota|balance|projects|radar")
            }
            return Self(command: command, value: args[1])
        case "size":
            guard args.count == 2, let level = Int(args[1]), (1...5).contains(level) else {
                throw CLIError.message("用法：size 1..5")
            }
            return Self(command: command, value: "level\(level)")
        case "move":
            guard args.count == 3, let x = Double(args[1]), let y = Double(args[2]),
                  x.isFinite, y.isFinite, abs(x) <= 1_000_000, abs(y) <= 1_000_000 else {
                throw CLIError.message("用法：move X Y；屏幕逻辑点，原点在主屏左下角")
            }
            return Self(command: command, x: x, y: y)
        default: throw CLIError.message("未知命令：\(command)")
        }
    }

    // Validate socket requests as strictly as local command-line arguments.
    func validated() throws -> Self {
        switch command {
        case "show": return try Self.parse([command, value ?? ""])
        case "size":
            guard let value, CompactPanelSize(rawValue: value) != nil else { throw CLIError.message("无效尺寸") }
            return self
        case "move": return try Self.parse([command, x.map(String.init(describing:)) ?? "", y.map(String.init(describing:)) ?? ""])
        default: return try Self.parse([command])
        }
    }
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case let .message(text): return text } }
}

enum EnergyCLI {
    static let help = """
    算力环本地 CLI（控制已经运行的应用；JSON 输出）
      energyctl status                       查询窗口、额度摘要、雷达状态
      energyctl show compact|quota|balance|projects|radar
      energyctl hide                         隐藏浮窗
      energyctl size 1..5                     设置现有五档尺寸
      energyctl move X Y                      移动并保存位置（屏幕逻辑点，左下原点）
      energyctl refresh                      请求刷新当前页（不等待网络完成）
      energyctl snapshot                     将当前浮窗渲染为 PNG（开发检查用）
      energyctl help
    本地 Unix socket，只允许同一用户访问，无 TCP/HTTP 端口。
    """

    static func run(_ args: [String]) -> Int32 {
        if args == ["help"] || args == ["--help"] { print(help); return 0 }
        do {
            let request = try EnergyCLIRequest.parse(args)
            let response = try LocalControlServer.call(request)
            print(String(decoding: response, as: UTF8.self))
            let result = try JSONSerialization.jsonObject(with: response) as? [String: Any]
            return result?["ok"] as? Bool == true ? 0 : 1
        } catch {
            let data = try! JSONSerialization.data(withJSONObject: ["ok": false, "error": String(describing: error)], options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return 1
        }
    }
}
