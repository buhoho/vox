import ArgumentParser
import VoxLib

@main
struct VoxCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vox",
        abstract: "macOS ローカル音声入力ツール",
        version: "0.1.0"
    )

    func run() throws {
        print("Vox v0.1.0")
    }
}
