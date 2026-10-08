import Foundation

enum TokenKind {
    case keyword, string, number, comment, type, function, constant, property, tag, attribute
}

struct LanguageSpec {
    var keywords: Set<String> = []
    var constants: Set<String> = []
    var builtinTypes: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    var quotes: [String] = ["\"", "'"]
    var multilineQuotes: [String] = []
    /// `key:` is highlighted as a property (JSON, YAML, CSS).
    var keyColon = false
    var caseInsensitive = false
    var variablePrefixes: [Character] = []
    /// `#include`-style directives at the start of a line.
    var preprocessor = false
    var identifierExtras: [Character] = []
    var markup = false
}

struct CodeLanguage {
    let id: String
    let name: String
    let aliases: [String]
    let spec: LanguageSpec

    static func find(_ raw: String) -> CodeLanguage? {
        let key = raw.lowercased()
        guard !key.isEmpty else { return nil }
        return all.first { $0.id == key || $0.aliases.contains(key) }
    }

    /// Label shown on a code block's language pill.
    static func label(for raw: String) -> String {
        if raw.isEmpty { return "text" }
        return (find(raw)?.name ?? raw).lowercased()
    }

    private static func words(_ s: String) -> Set<String> {
        Set(s.split(separator: " ").map(String.init))
    }

    private static let cKeywords = "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while"

    private static let jsKeywords = "break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new of return super switch this throw try typeof var void while with yield async await static get set from as"

    static let all: [CodeLanguage] = [
        CodeLanguage(id: "bash", name: "Bash", aliases: ["sh", "shell", "zsh", "console"], spec: LanguageSpec(
            keywords: words("if then else elif fi case esac for select while until do done in function time return exit export local readonly declare unset source alias echo cd set shift trap eval exec printf read"),
            constants: words("true false"),
            lineComments: ["#"],
            variablePrefixes: ["$"])),
        CodeLanguage(id: "c", name: "C", aliases: ["h"], spec: LanguageSpec(
            keywords: words(cKeywords),
            constants: words("NULL true false"),
            builtinTypes: words("size_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t bool FILE"),
            lineComments: ["//"], blockComment: ("/*", "*/"),
            preprocessor: true)),
        CodeLanguage(id: "cpp", name: "C++", aliases: ["c++", "cc", "cxx", "hpp"], spec: LanguageSpec(
            keywords: words(cKeywords + " alignas alignof asm bool catch class constexpr const_cast consteval constinit decltype delete dynamic_cast explicit export friend mutable namespace new noexcept operator private protected public reinterpret_cast static_assert static_cast template this thread_local throw try typeid typename using virtual override final co_await co_return co_yield concept requires"),
            constants: words("true false nullptr NULL"),
            builtinTypes: words("size_t string vector map set unordered_map unique_ptr shared_ptr int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t std"),
            lineComments: ["//"], blockComment: ("/*", "*/"),
            preprocessor: true)),
        CodeLanguage(id: "csharp", name: "C#", aliases: ["cs", "c#"], spec: LanguageSpec(
            keywords: words("abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw try typeof uint ulong unchecked unsafe ushort using virtual void volatile while var async await get set record init yield"),
            constants: words("true false null"),
            lineComments: ["//"], blockComment: ("/*", "*/"),
            preprocessor: true)),
        CodeLanguage(id: "css", name: "CSS", aliases: ["scss", "less"], spec: LanguageSpec(
            constants: words("important auto none inherit initial unset"),
            blockComment: ("/*", "*/"),
            keyColon: true,
            identifierExtras: ["-"])),
        CodeLanguage(id: "go", name: "Go", aliases: ["golang"], spec: LanguageSpec(
            keywords: words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"),
            constants: words("true false nil iota"),
            builtinTypes: words("string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr float32 float64 complex64 complex128 bool byte rune error any"),
            lineComments: ["//"], blockComment: ("/*", "*/"),
            multilineQuotes: ["`"])),
        CodeLanguage(id: "html", name: "HTML", aliases: ["xml", "svg", "xhtml", "vue"], spec: LanguageSpec(markup: true)),
        CodeLanguage(id: "java", name: "Java", aliases: [], spec: LanguageSpec(
            keywords: words("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while var record sealed permits yield"),
            constants: words("true false null"),
            lineComments: ["//"], blockComment: ("/*", "*/"),
            multilineQuotes: ["\"\"\""])),
        CodeLanguage(id: "javascript", name: "JavaScript", aliases: ["js", "jsx", "mjs", "cjs"], spec: LanguageSpec(
            keywords: words(jsKeywords),
            constants: words("true false null undefined NaN Infinity"),
            lineComments: ["//"], blockComment: ("/*", "*/"),
            multilineQuotes: ["`"],
            variablePrefixes: [])),
        CodeLanguage(id: "json", name: "JSON", aliases: ["jsonc", "json5"], spec: LanguageSpec(
            constants: words("true false null"),
            lineComments: ["//"],
            quotes: ["\""],
            keyColon: true)),
        CodeLanguage(id: "kotlin", name: "Kotlin", aliases: ["kt", "kts"], spec: LanguageSpec(
            keywords: words("as break class continue do else for fun if in interface is object package return super this throw try typealias val var when while by catch constructor finally get import init set where abstract annotation companion const data enum external final infix inline inner internal lateinit open operator out override private protected public reified sealed suspend tailrec vararg"),
            constants: words("true false null"),
            lineComments: ["//"], blockComment: ("/*", "*/"),
            multilineQuotes: ["\"\"\""])),
        CodeLanguage(id: "lua", name: "Lua", aliases: [], spec: LanguageSpec(
            keywords: words("and break do else elseif end for function goto if in local not or repeat return then until while"),
            constants: words("true false nil"),
            lineComments: ["--"], blockComment: ("--[[", "]]"))),
        CodeLanguage(id: "php", name: "PHP", aliases: [], spec: LanguageSpec(
            keywords: words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty extends final finally fn for foreach function global goto if implements include include_once instanceof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield"),
            constants: words("true false null TRUE FALSE NULL"),
            lineComments: ["//", "#"], blockComment: ("/*", "*/"),
            variablePrefixes: ["$"])),
        CodeLanguage(id: "python", name: "Python", aliases: ["py", "python3"], spec: LanguageSpec(
            keywords: words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case self cls"),
            constants: words("True False None"),
            builtinTypes: words("int float str bool list dict set tuple bytes object"),
            lineComments: ["#"],
            multilineQuotes: ["\"\"\"", "'''"])),
        CodeLanguage(id: "ruby", name: "Ruby", aliases: ["rb"], spec: LanguageSpec(
            keywords: words("alias and begin break case class def defined do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield require attr_accessor attr_reader attr_writer puts"),
            constants: words("true false nil"),
            lineComments: ["#"])),
        CodeLanguage(id: "rust", name: "Rust", aliases: ["rs"], spec: LanguageSpec(
            keywords: words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while"),
            constants: words("true false None Some Ok Err"),
            builtinTypes: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str"),
            lineComments: ["//"], blockComment: ("/*", "*/"),
            quotes: ["\""])),
        CodeLanguage(id: "sql", name: "SQL", aliases: ["sqlite", "postgres", "postgresql", "mysql", "psql"], spec: LanguageSpec(
            keywords: words("select from where insert into values update set delete create table drop alter add column index view join inner left right outer full cross on as and or not is in exists between like ilike group by order having limit offset union all distinct case when then else end primary key foreign references default unique check constraint begin commit rollback transaction with returning if replace asc desc count sum avg min max cast integer int text real blob varchar boolean date timestamp serial"),
            constants: words("true false null"),
            lineComments: ["--"], blockComment: ("/*", "*/"),
            caseInsensitive: true)),
        CodeLanguage(id: "swift", name: "Swift", aliases: [], spec: LanguageSpec(
            keywords: words("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as is try await async throws some any super self Self mutating nonmutating lazy weak unowned override final required convenience dynamic indirect get set willSet didSet actor nonisolated isolated consuming borrowing macro"),
            constants: words("true false nil"),
            lineComments: ["//"], blockComment: ("/*", "*/"),
            quotes: ["\""],
            multilineQuotes: ["\"\"\""])),
        CodeLanguage(id: "typescript", name: "TypeScript", aliases: ["ts", "tsx", "mts"], spec: LanguageSpec(
            keywords: words(jsKeywords + " interface type enum implements namespace declare abstract private protected public readonly keyof infer is satisfies"),
            constants: words("true false null undefined NaN Infinity"),
            builtinTypes: words("any unknown never string number boolean symbol object bigint void"),
            lineComments: ["//"], blockComment: ("/*", "*/"),
            multilineQuotes: ["`"])),
        CodeLanguage(id: "yaml", name: "YAML", aliases: ["yml"], spec: LanguageSpec(
            constants: words("true false null yes no on off"),
            lineComments: ["#"],
            keyColon: true,
            identifierExtras: ["-", "."])),
    ]
}
