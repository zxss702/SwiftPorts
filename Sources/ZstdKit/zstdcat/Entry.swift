import ZstdCommand

@main
struct Entry {
    static func main() async {
        await Zstdcat.main()
    }
}
