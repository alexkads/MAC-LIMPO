import Foundation

class ShellExecutor {
    static let shared = ShellExecutor()

    @discardableResult
    func execute(
        _ command: String,
        requiresSudo _: Bool = false,
        timeout: TimeInterval = 60
    ) -> (output: String, error: String, exitCode: Int32) {
        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.standardOutput = outputPipe
        task.standardError = errorPipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        task.standardInput = nil

        // Configura ambiente com PATH completo para encontrar tools (brew, docker, etc)
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        let additionalPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(NSHomeDirectory())/.cargo/bin"
        ]
        let newPath = additionalPaths.joined(separator: ":") + ":" + existingPath
        env["PATH"] = newPath
        task.environment = env

        // Sinaliza quando o processo termina (sem busy-wait com Thread.sleep).
        let exitSemaphore = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exitSemaphore.signal() }

        // Drena os pipes em threads separadas. Ler só depois de o processo sair
        // (código antigo) trava se a saída passar de ~64KB e encher o buffer do
        // pipe enquanto o processo ainda escreve.
        var outputData = Data()
        var errorData = Data()
        let ioGroup = DispatchGroup()
        let ioQueue = DispatchQueue(label: "com.maclimpo.shell.io", attributes: .concurrent)
        ioQueue.async(group: ioGroup) { outputData = outputPipe.fileHandleForReading.readDataToEndOfFile() }
        ioQueue.async(group: ioGroup) { errorData = errorPipe.fileHandleForReading.readDataToEndOfFile() }

        do {
            try task.run()
        } catch {
            return ("", error.localizedDescription, -1)
        }

        // Espera o término respeitando o timeout.
        if exitSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            ioGroup.wait() // pipes fecham no terminate; deixa as leituras encerrarem
            return ("", "Command timed out after \(timeout) seconds", -1)
        }

        ioGroup.wait() // garante leitura completa da saída antes de retornar
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        return (output, error, task.terminationStatus)
    }

    func checkCommandExists(_ command: String) -> Bool {
        let result = execute("which \(command)", timeout: 5)
        return result.exitCode == 0
    }
}
