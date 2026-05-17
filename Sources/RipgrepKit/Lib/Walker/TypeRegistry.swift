import Foundation

/// File-type registry powering `rg --type=swift`, `--type-not=js`,
/// `--type-list`, and `--type-add tag:glob`.
///
/// The default table mirrors `BurntSushi/ripgrep`'s
/// `crates/ignore/src/default_types.rs` (the entries the user is most
/// likely to reach for — full parity is impractical and unnecessary
/// since `--type-add` lets users add anything missing). Both the
/// name → globs mapping and the user-visible help list come from the
/// same source so they cannot drift.
public struct TypeRegistry: Sendable {

    /// One typedef. `aliases` lets `markdown` and `md` resolve to the
    /// same set of globs without duplicating the entry.
    public struct TypeDef: Sendable {
        public let aliases: [String]
        public var globs: [String]

        public init(aliases: [String], globs: [String]) {
            self.aliases = aliases
            self.globs = globs
        }
    }

    public private(set) var defs: [TypeDef]

    public init(defs: [TypeDef]) {
        self.defs = defs
    }

    /// Default registry — the BurntSushi/ripgrep upstream defaults.
    public static let `default` = TypeRegistry(defs: TypeRegistry.defaults)

    /// Compile name into globs. Resolves through the `aliases` list.
    public func globs(forType name: String) -> [String]? {
        for def in defs where def.aliases.contains(name) {
            return def.globs
        }
        return nil
    }

    /// Add a `tag:glob` typespec. `tag:include:other` chains another
    /// type into this one (matches ripgrep's `--type-add` syntax).
    public mutating func add(_ spec: String) throws {
        guard let sep = spec.firstIndex(of: ":") else {
            throw TypeRegistryError.invalidSpec(spec)
        }
        let name = String(spec[..<sep]).trimmingCharacters(in: .whitespaces)
        let rest = String(spec[spec.index(after: sep)...])
        guard !name.isEmpty else {
            throw TypeRegistryError.invalidSpec(spec)
        }
        if rest.hasPrefix("include:") {
            let included = String(rest.dropFirst("include:".count))
            guard let g = globs(forType: included) else {
                throw TypeRegistryError.unknownType(included)
            }
            mergeGlobs(g, into: name)
        } else {
            mergeGlobs([rest], into: name)
        }
    }

    /// Clear globs for `name` (also removes its aliases).
    public mutating func clear(_ name: String) {
        defs.removeAll { $0.aliases.contains(name) }
    }

    /// Sorted list of `(name, globs)` for `--type-list` output.
    public func listing() -> [(String, [String])] {
        defs
            .map { (alias: $0.aliases.first ?? "?", globs: $0.globs) }
            .sorted { $0.alias < $1.alias }
    }

    /// All known names (including aliases).
    public func allNames() -> Set<String> {
        var names: Set<String> = []
        for def in defs { names.formUnion(def.aliases) }
        return names
    }

    private mutating func mergeGlobs(_ globs: [String], into name: String) {
        if let idx = defs.firstIndex(where: { $0.aliases.contains(name) }) {
            for g in globs where !defs[idx].globs.contains(g) {
                defs[idx].globs.append(g)
            }
            return
        }
        defs.append(TypeDef(aliases: [name], globs: globs))
    }
}

public enum TypeRegistryError: Error, CustomStringConvertible, Sendable {
    case invalidSpec(String)
    case unknownType(String)

    public var description: String {
        switch self {
        case let .invalidSpec(s):
            return "invalid --type-add value: \(s)"
        case let .unknownType(t):
            return "unrecognized file type: \(t)"
        }
    }
}

extension TypeRegistry {
    /// The default file-type table. Lifted verbatim (in spirit) from
    /// BurntSushi/ripgrep's `default_types.rs`. Keep it sorted by the
    /// first alias.
    static let defaults: [TypeDef] = [
        TypeDef(aliases: ["ada"], globs: ["*.adb", "*.ads"]),
        TypeDef(aliases: ["agda"], globs: ["*.agda", "*.lagda"]),
        TypeDef(aliases: ["aidl"], globs: ["*.aidl"]),
        TypeDef(aliases: ["asciidoc"], globs: ["*.adoc", "*.asc", "*.asciidoc"]),
        TypeDef(aliases: ["asm"], globs: ["*.asm", "*.s", "*.S"]),
        TypeDef(aliases: ["bat", "batch"], globs: ["*.bat"]),
        TypeDef(aliases: ["bazel"],
                globs: ["*.bazel", "*.bzl", "BUILD", "BUILD.bazel",
                        "WORKSPACE", "WORKSPACE.bazel", "MODULE.bazel"]),
        TypeDef(aliases: ["bitbake"],
                globs: ["*.bb", "*.bbappend", "*.bbclass", "*.conf", "*.inc"]),
        TypeDef(aliases: ["brotli"], globs: ["*.br"]),
        TypeDef(aliases: ["bzip2"], globs: ["*.bz2", "*.tbz2"]),
        TypeDef(aliases: ["c"], globs: ["*.c", "*.h", "*.H"]),
        TypeDef(aliases: ["cabal"], globs: ["*.cabal"]),
        TypeDef(aliases: ["cbor"], globs: ["*.cbor"]),
        TypeDef(aliases: ["clojure"],
                globs: ["*.clj", "*.cljc", "*.cljs", "*.cljx"]),
        TypeDef(aliases: ["cmake"], globs: ["*.cmake", "CMakeLists.txt"]),
        TypeDef(aliases: ["coffeescript"], globs: ["*.coffee"]),
        TypeDef(aliases: ["config"], globs: ["*.cfg", "*.conf", "*.config", "*.ini"]),
        TypeDef(aliases: ["cpp"],
                globs: ["*.cc", "*.cpp", "*.cxx", "*.hpp", "*.hxx", "*.hh", "*.inl"]),
        TypeDef(aliases: ["crystal"], globs: ["*.cr", "Projectfile", "shard.yml"]),
        TypeDef(aliases: ["cs", "csharp"], globs: ["*.cs"]),
        TypeDef(aliases: ["csproj"], globs: ["*.csproj"]),
        TypeDef(aliases: ["css"], globs: ["*.css", "*.scss"]),
        TypeDef(aliases: ["csv"], globs: ["*.csv"]),
        TypeDef(aliases: ["cuda"], globs: ["*.cu", "*.cuh"]),
        TypeDef(aliases: ["d"], globs: ["*.d"]),
        TypeDef(aliases: ["dart"], globs: ["*.dart"]),
        TypeDef(aliases: ["diff"], globs: ["*.patch", "*.diff"]),
        TypeDef(aliases: ["docker"], globs: ["Dockerfile", "*.dockerfile"]),
        TypeDef(aliases: ["dts"], globs: ["*.dts", "*.dtsi"]),
        TypeDef(aliases: ["elixir"],
                globs: ["*.ex", "*.exs", "*.eex", "*.heex", "*.leex", "*.livemd"]),
        TypeDef(aliases: ["elm"], globs: ["*.elm"]),
        TypeDef(aliases: ["erb"], globs: ["*.erb"]),
        TypeDef(aliases: ["erlang"], globs: ["*.erl", "*.hrl"]),
        TypeDef(aliases: ["fish"], globs: ["*.fish"]),
        TypeDef(aliases: ["fortran"],
                globs: ["*.f", "*.F", "*.f77", "*.F77",
                        "*.f90", "*.F90", "*.f95", "*.F95"]),
        TypeDef(aliases: ["fsharp"], globs: ["*.fs", "*.fsx", "*.fsi"]),
        TypeDef(aliases: ["gn"], globs: ["*.gn", "*.gni"]),
        TypeDef(aliases: ["go"], globs: ["*.go"]),
        TypeDef(aliases: ["gradle"],
                globs: ["*.gradle", "*.gradle.kts", "gradle.properties"]),
        TypeDef(aliases: ["graphql"], globs: ["*.graphql", "*.graphqls"]),
        TypeDef(aliases: ["groovy"], globs: ["*.groovy", "*.gradle"]),
        TypeDef(aliases: ["gzip"], globs: ["*.gz", "*.tgz"]),
        TypeDef(aliases: ["h"], globs: ["*.h", "*.hh", "*.hpp"]),
        TypeDef(aliases: ["haml"], globs: ["*.haml"]),
        TypeDef(aliases: ["haskell"],
                globs: ["*.hs", "*.lhs", "*.cpphs", "*.c2hs", "*.hsc"]),
        TypeDef(aliases: ["html"], globs: ["*.htm", "*.html", "*.ejs"]),
        TypeDef(aliases: ["java"],
                globs: ["*.java", "*.jsp", "*.jspx", "*.properties"]),
        TypeDef(aliases: ["js"],
                globs: ["*.js", "*.jsx", "*.vue", "*.cjs", "*.mjs"]),
        TypeDef(aliases: ["json"], globs: ["*.json", "composer.lock", "*.sarif"]),
        TypeDef(aliases: ["jsonl"], globs: ["*.jsonl"]),
        TypeDef(aliases: ["julia"], globs: ["*.jl"]),
        TypeDef(aliases: ["jupyter"], globs: ["*.ipynb", "*.jpynb"]),
        TypeDef(aliases: ["kotlin"], globs: ["*.kt", "*.kts"]),
        TypeDef(aliases: ["less"], globs: ["*.less"]),
        TypeDef(aliases: ["lisp"],
                globs: ["*.el", "*.jl", "*.lisp", "*.lsp", "*.sc", "*.scm"]),
        TypeDef(aliases: ["lock"], globs: ["*.lock", "package-lock.json"]),
        TypeDef(aliases: ["log"], globs: ["*.log"]),
        TypeDef(aliases: ["lua"], globs: ["*.lua"]),
        TypeDef(aliases: ["lz4"], globs: ["*.lz4"]),
        TypeDef(aliases: ["lzma"], globs: ["*.lzma"]),
        TypeDef(aliases: ["m4"], globs: ["*.ac", "*.m4"]),
        TypeDef(aliases: ["make"],
                globs: ["[Mm]akefile", "[Mm]akefile.*", "*.mk", "*.mak"]),
        TypeDef(aliases: ["markdown", "md"],
                globs: ["*.markdown", "*.md", "*.mdown", "*.mdwn",
                        "*.mkd", "*.mkdn", "*.mdx"]),
        TypeDef(aliases: ["matlab"], globs: ["*.m"]),
        TypeDef(aliases: ["meson"], globs: ["meson.build", "meson_options.txt"]),
        TypeDef(aliases: ["nim"], globs: ["*.nim", "*.nimble", "*.nims"]),
        TypeDef(aliases: ["nix"], globs: ["*.nix"]),
        TypeDef(aliases: ["objc"], globs: ["*.h", "*.m"]),
        TypeDef(aliases: ["objcpp"], globs: ["*.h", "*.mm"]),
        TypeDef(aliases: ["ocaml"], globs: ["*.ml", "*.mli", "*.mll", "*.mly"]),
        TypeDef(aliases: ["org"], globs: ["*.org"]),
        TypeDef(aliases: ["pascal"], globs: ["*.pas", "*.dpr", "*.lpr", "*.pp"]),
        TypeDef(aliases: ["pdf"], globs: ["*.pdf"]),
        TypeDef(aliases: ["perl"],
                globs: ["*.perl", "*.pl", "*.plh", "*.plx", "*.pm", "*.t"]),
        TypeDef(aliases: ["php"],
                globs: ["*.php", "*.php3", "*.php4", "*.php5",
                        "*.phtml"]),
        TypeDef(aliases: ["po"], globs: ["*.po"]),
        TypeDef(aliases: ["pod"], globs: ["*.pod"]),
        TypeDef(aliases: ["protobuf"], globs: ["*.proto"]),
        TypeDef(aliases: ["ps"],
                globs: ["*.ps1", "*.ps1xml", "*.psd1", "*.psm1"]),
        TypeDef(aliases: ["puppet"], globs: ["*.epp", "*.erb", "*.pp", "*.rb"]),
        TypeDef(aliases: ["purs"], globs: ["*.purs"]),
        TypeDef(aliases: ["py", "python"], globs: ["*.py", "*.pyi"]),
        TypeDef(aliases: ["qmake"], globs: ["*.pro", "*.pri", "*.prf"]),
        TypeDef(aliases: ["qml"], globs: ["*.qml"]),
        TypeDef(aliases: ["r"], globs: ["*.R", "*.r", "*.Rmd", "*.Rnw"]),
        TypeDef(aliases: ["raku"],
                globs: ["*.raku", "*.rakumod", "*.rakudoc", "*.rakutest",
                        "*.p6", "*.pl6", "*.pm6"]),
        TypeDef(aliases: ["readme"], globs: ["README*", "*README"]),
        TypeDef(aliases: ["rst"], globs: ["*.rst"]),
        TypeDef(aliases: ["ruby"],
                globs: ["config.ru", "Gemfile", ".irbrc", "Rakefile",
                        "*.gemspec", "*.rb", "*.rbw", "*.rake"]),
        TypeDef(aliases: ["rust"], globs: ["*.rs"]),
        TypeDef(aliases: ["sass"], globs: ["*.sass", "*.scss"]),
        TypeDef(aliases: ["scala"], globs: ["*.scala", "*.sbt"]),
        TypeDef(aliases: ["sh"],
                globs: ["*.bash", "*.csh", "*.ksh", "*.sh", "*.tcsh",
                        "*.zsh", ".bashrc", ".bash_profile", ".bash_logout",
                        ".profile", ".zshrc", ".zshenv", ".zprofile",
                        ".zlogin", ".zlogout"]),
        TypeDef(aliases: ["smarty"], globs: ["*.tpl"]),
        TypeDef(aliases: ["sml"], globs: ["*.sml", "*.sig"]),
        TypeDef(aliases: ["solidity"], globs: ["*.sol"]),
        TypeDef(aliases: ["sql"], globs: ["*.sql", "*.psql"]),
        TypeDef(aliases: ["stylus"], globs: ["*.styl"]),
        TypeDef(aliases: ["sv"], globs: ["*.v", "*.vg", "*.sv", "*.svh"]),
        TypeDef(aliases: ["svelte"], globs: ["*.svelte"]),
        TypeDef(aliases: ["svg"], globs: ["*.svg"]),
        TypeDef(aliases: ["swift"], globs: ["*.swift"]),
        TypeDef(aliases: ["systemd"],
                globs: ["*.automount", "*.device", "*.link", "*.mount",
                        "*.path", "*.scope", "*.service", "*.slice",
                        "*.socket", "*.swap", "*.target", "*.timer"]),
        TypeDef(aliases: ["tcl"], globs: ["*.tcl"]),
        TypeDef(aliases: ["tex"],
                globs: ["*.tex", "*.ltx", "*.cls", "*.sty", "*.bib"]),
        TypeDef(aliases: ["textile"], globs: ["*.textile"]),
        TypeDef(aliases: ["tf"],
                globs: ["*.tf", "*.tf.json", "*.tfvars", "*.tfvars.json"]),
        TypeDef(aliases: ["thrift"], globs: ["*.thrift"]),
        TypeDef(aliases: ["toml"], globs: ["*.toml", "Cargo.lock"]),
        TypeDef(aliases: ["ts", "typescript"],
                globs: ["*.ts", "*.tsx", "*.cts", "*.mts"]),
        TypeDef(aliases: ["twig"], globs: ["*.twig"]),
        TypeDef(aliases: ["txt"], globs: ["*.txt"]),
        TypeDef(aliases: ["typst"], globs: ["*.typ"]),
        TypeDef(aliases: ["vala"], globs: ["*.vala"]),
        TypeDef(aliases: ["vb"], globs: ["*.vb"]),
        TypeDef(aliases: ["verilog"], globs: ["*.v", "*.vh", "*.sv", "*.svh"]),
        TypeDef(aliases: ["vhdl"], globs: ["*.vhd", "*.vhdl"]),
        TypeDef(aliases: ["vim"], globs: ["*.vim"]),
        TypeDef(aliases: ["vue"], globs: ["*.vue"]),
        TypeDef(aliases: ["wgsl"], globs: ["*.wgsl"]),
        TypeDef(aliases: ["xml"],
                globs: ["*.xml", "*.xml.dist", "*.dtd", "*.xsl", "*.xslt",
                        "*.xsd", "*.rng", "*.sch", "*.xhtml"]),
        TypeDef(aliases: ["xz"], globs: ["*.xz", "*.txz"]),
        TypeDef(aliases: ["yacc"], globs: ["*.y"]),
        TypeDef(aliases: ["yaml"], globs: ["*.yaml", "*.yml"]),
        TypeDef(aliases: ["zig"], globs: ["*.zig"]),
        TypeDef(aliases: ["zsh"],
                globs: [".zshenv", ".zlogin", ".zlogout", ".zprofile",
                        ".zshrc", "*.zsh"]),
        TypeDef(aliases: ["zstd"], globs: ["*.zst", "*.zstd"]),
    ]
}
