import ArgumentParser
import Foundation
import JqKit
import Sandbox

/// `jq [OPTIONS] FILTER [FILE...]` — command-line JSON processor.
///
/// A native Swift implementation that mirrors stedolan/jq's surface
/// area: a recursive-descent parser, a streaming evaluator, and the
/// full builtin library (math, type, string, array, object, control,
/// path, navigation, SQL, date, formatters).
///
/// Supported options: `-r`/`--raw-output`, `-c`/`--compact-output`,
/// `-e`/`--exit-status`, `-s`/`--slurp`, `-n`/`--null-input`,
/// `-j`/`--join-output`, `-S`/`--sort-keys`, `-R`/`--raw-input`,
/// `--tab`, `--indent N`, `--arg NAME VALUE`, `--argjson NAME VALUE`,
/// `--slurpfile NAME FILE`, `--rawfile NAME FILE`,
/// `--args`/`--jsonargs` (positional). Color flags (`-C`, `-M`, `-a`)
/// are accepted but ignored.
///
/// Flags can appear anywhere on the command line, matching jq's
/// behaviour — that's why we hand-parse argv instead of using
/// `@Flag` declarations.
public struct Jq: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "jq",
        abstract: "Command-line JSON processor."
    )

    @Argument(parsing: .captureForPassthrough,
              help: "OPTIONS, FILTER, FILE…")
    public var rawArgv: [String] = []

    public init() {}

    public func run() async throws {
        let exit = try await JqExecutable.run(argv: rawArgv)
        if exit != 0 {
            throw ExitCode(exit)
        }
    }
}

/// Engine shared between the `Jq` AsyncParsableCommand and any
/// embedder that wants to drive the CLI behavior in-process.
///
/// Returns the exit code. 0 = success, 1 = `--exit-status` saw all-falsy
/// output, 2 = bad argv / IO, 3 = filter parse error, 5 = runtime error.
public enum JqExecutable {

    public static func run(argv: [String],
                           stdin: FileHandle = .standardInput,
                           stdout: FileHandle = .standardOutput,
                           stderr: FileHandle = .standardError) async throws -> Int32 {
        var raw = false
        var rawInput = false
        var compact = false
        var exitStatus = false
        var slurp = false
        var nullInput = false
        var joinOutput = false
        var sortKeys = false
        var useTab = false
        var indent = 2

        var filter: String? = nil
        var files: [String] = []
        var namedArgs: [String: JqValue] = [:]
        var positional: [JqValue] = []
        var inArgsMode: ArgsMode = .none

        func writeErr(_ s: String) { stderr.write(Data(s.utf8)) }
        func writeOut(_ s: String) { stdout.write(Data(s.utf8)) }

        var i = 0
        while i < argv.count {
            let a = argv[i]
            switch inArgsMode {
            case .args:
                positional.append(.string(a))
                i += 1
                continue
            case .jsonargs:
                if let v = try? JqJSON.parse(a) {
                    positional.append(v)
                } else {
                    writeErr("jq: invalid JSON in --jsonargs: \(a)\n")
                    return 2
                }
                i += 1
                continue
            case .none:
                break
            }

            switch a {
            case "--raw-output": raw = true; i += 1; continue
            case "--raw-input": rawInput = true; i += 1; continue
            case "--compact-output": compact = true; i += 1; continue
            case "--exit-status": exitStatus = true; i += 1; continue
            case "--slurp": slurp = true; i += 1; continue
            case "--null-input": nullInput = true; i += 1; continue
            case "--join-output": joinOutput = true; i += 1; continue
            case "--ascii-output": i += 1; continue
            case "--sort-keys": sortKeys = true; i += 1; continue
            case "--color-output", "--monochrome-output": i += 1; continue
            case "--tab": useTab = true; i += 1; continue
            case "--indent":
                guard i + 1 < argv.count, let n = Int(argv[i + 1]) else {
                    writeErr("jq: --indent requires a number\n")
                    return 2
                }
                indent = n; i += 2; continue
            case "--arg":
                guard i + 2 < argv.count else {
                    writeErr("jq: --arg requires NAME VALUE\n")
                    return 2
                }
                namedArgs[argv[i + 1]] = .string(argv[i + 2])
                i += 3; continue
            case "--argjson":
                guard i + 2 < argv.count else {
                    writeErr("jq: --argjson requires NAME VALUE\n")
                    return 2
                }
                if let v = try? JqJSON.parse(argv[i + 2]) {
                    namedArgs[argv[i + 1]] = v
                } else {
                    writeErr("jq: invalid JSON for --argjson \(argv[i + 1])\n")
                    return 2
                }
                i += 3; continue
            case "--slurpfile", "--rawfile":
                guard i + 2 < argv.count else {
                    writeErr("jq: \(a) requires NAME FILE\n")
                    return 2
                }
                let name = argv[i + 1]
                let path = argv[i + 2]
                do {
                    let url = Sandbox.resolve(path)
                    try await Sandbox.authorize(url)
                    let data = try Data(contentsOf: url)
                    let text = String(decoding: data, as: UTF8.self)
                    if a == "--slurpfile" {
                        let vs = try JqJSON.parseStream(text)
                        namedArgs[name] = .array(vs)
                    } else {
                        namedArgs[name] = .string(text)
                    }
                } catch {
                    writeErr("jq: cannot read file \(path): \(error)\n")
                    return 2
                }
                i += 3; continue
            case "--args": inArgsMode = .args; i += 1; continue
            case "--jsonargs": inArgsMode = .jsonargs; i += 1; continue
            case "--help":
                writeOut("jq - command-line JSON processor\n")
                return 0
            case "--version":
                writeOut("jq-1.7 (swift-ports)\n")
                return 0
            default: break
            }

            if a == "-" {
                files.append("-"); i += 1; continue
            }
            if a.hasPrefix("-") && !a.hasPrefix("--") && a.count > 1 {
                let chars = Array(a.dropFirst())
                var unknown = false
                for c in chars {
                    switch c {
                    case "r": raw = true
                    case "R": rawInput = true
                    case "c": compact = true
                    case "e": exitStatus = true
                    case "s": slurp = true
                    case "n": nullInput = true
                    case "j": joinOutput = true
                    case "a": break
                    case "S": sortKeys = true
                    case "C", "M": break
                    default: unknown = true
                    }
                }
                if unknown {
                    writeErr("jq: invalid option: \(a)\n")
                    return 2
                }
                i += 1
                continue
            }
            if a.hasPrefix("--") {
                writeErr("jq: unknown option: \(a)\n")
                return 2
            }

            if filter == nil {
                filter = a
            } else {
                files.append(a)
            }
            i += 1
        }
        let filterStr = filter ?? "."

        let ast: JqAST
        do {
            ast = try JqParser.parse(filterStr)
        } catch let e as JqError {
            writeErr("jq: \(e.message)\n")
            return 3
        } catch {
            writeErr("jq: \(error)\n")
            return 3
        }

        var inputContents: [String] = []
        if nullInput {
            // no inputs
        } else if files.isEmpty || (files.count == 1 && files[0] == "-") {
            inputContents.append(readStdinString(stdin))
        } else {
            for f in files {
                if f == "-" {
                    inputContents.append(readStdinString(stdin))
                    continue
                }
                do {
                    let url = Sandbox.resolve(f)
                    try await Sandbox.authorize(url)
                    let data = try Data(contentsOf: url)
                    inputContents.append(String(decoding: data, as: UTF8.self))
                } catch {
                    writeErr("jq: error: cannot read file \(f): \(error)\n")
                    return 2
                }
            }
        }

        var values: [JqValue] = []
        do {
            if nullInput {
                values = [.null]
            } else if rawInput {
                if slurp {
                    values = [.string(inputContents.joined())]
                } else {
                    let combined = inputContents.joined()
                    values = combined.split(omittingEmptySubsequences: false,
                                            whereSeparator: { $0 == "\n" })
                        .map { .string(String($0)) }
                    if values.last == .string("") { values.removeLast() }
                }
            } else if slurp {
                var slurped: [JqValue] = []
                for c in inputContents {
                    try Task.checkCancellation()
                    let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        slurped.append(contentsOf: try JqJSON.parseStream(c))
                    }
                }
                values = [.array(slurped)]
            } else {
                for c in inputContents {
                    try Task.checkCancellation()
                    let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    values.append(contentsOf: try JqJSON.parseStream(c))
                }
            }
        } catch let e as JqError {
            writeErr("jq: \(e.message)\n")
            return 2
        } catch {
            writeErr("jq: \(error)\n")
            return 2
        }

        // jq's `env` / `$ENV` builtins read here. Going through
        // Sandbox.environment means a sandboxed task feeds an
        // empty (default-deny) env or the embedder-supplied env to
        // the filter — never leaking the host process's env.
        let env = Sandbox.environment

        var sharedVars: [String: JqValue] = [:]
        for (name, val) in namedArgs {
            sharedVars["$\(name)"] = val
        }
        var argsObj = JqObject()
        argsObj["positional"] = .array(positional)
        var named = JqObject()
        for (k, v) in namedArgs { named[k] = v }
        argsObj["named"] = .object(named)
        sharedVars["$ARGS"] = .object(argsObj)

        var allOutputs: [JqValue] = []
        for v in values {
            try Task.checkCancellation()
            do {
                let ctx = JqContext(env: env)
                ctx.vars = sharedVars
                let results = try JqEvaluator.evaluate(v, ast, ctx: ctx)
                allOutputs.append(contentsOf: results)
            } catch let e as JqError {
                writeErr("jq: error: \(e.message)\n")
                return 5
            } catch let e as JqThrown {
                writeErr("jq: error: \(e.description)\n")
                return 5
            } catch {
                writeErr("jq: error: \(error)\n")
                return 5
            }
        }

        let opts = JqFormatter.Options(
            compact: compact, raw: raw, sortKeys: sortKeys,
            useTab: useTab, indent: indent)
        var out = ""
        for v in allOutputs {
            try Task.checkCancellation()
            out += JqFormatter.format(v, options: opts)
            if !joinOutput {
                out += "\n"
            }
        }
        writeOut(out)

        if exitStatus {
            let allFalsy = allOutputs.isEmpty || allOutputs.allSatisfy { v in
                switch v {
                case .null, .bool(false): return true
                default: return false
                }
            }
            return allFalsy ? 1 : 0
        }
        return 0
    }

    private enum ArgsMode { case none, args, jsonargs }

    private static func readStdinString(_ handle: FileHandle) -> String {
        let data = handle.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
