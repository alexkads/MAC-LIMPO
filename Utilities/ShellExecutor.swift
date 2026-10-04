import Foundation

class ShellExecutor: @unchecked Sendable {
    private final class DataBox: @unchecked Sendable {
        var value = Data()
    }

    static let shared = ShellExecutor()

    /// Tempo que o processo tem para encerrar (e fechar os pipes) depois de um
    /// timeout, antes do SIGKILL e, por fim, de abandonarmos a espera.
    static let terminateGrace: TimeInterval = 2

    /// Executa um comando via `zsh -c`. Conveniente para pipelines, mas NÃO
    /// interpole paths do usuário aqui (aspas/espaços quebram); use `run(_:_:)`.
    @discardableResult
    func execute(
        _ command: String,
        requiresSudo _: Bool = false,
        timeout: TimeInterval = 60
    ) -> (output: String, error: String, exitCode: Int32) {
        run("/bin/zsh", ["-c", command], timeout: timeout)
    }

    /// Executa um binário diretamente com argumentos, sem passar por um shell.
    /// Seguro para paths arbitrários (não há interpolação/escaping a acertar).
    @discardableResult
    func run(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval = 60
    ) -> (output: String, error: String, exitCode: Int32) {
        let task = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.standardOutput = outputPipe
        task.standardError = errorPipe
        task.arguments = arguments
        task.launchPath = launchPath
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
        let outputData = DataBox()
        let errorData = DataBox()
        let ioGroup = DispatchGroup()
        let ioQueue = DispatchQueue(label: "com.maclimpo.shell.io", attributes: .concurrent)
        ioQueue.async(group: ioGroup) { outputData.value = outputPipe.fileHandleForReading.readDataToEndOfFile() }
        ioQueue.async(group: ioGroup) { errorData.value = errorPipe.fileHandleForReading.readDataToEndOfFile() }

        do {
            try task.run()
        } catch {
            return ("", error.localizedDescription, -1)
        }

        // Espera o término respeitando o timeout.
        if exitSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            // Os pipes normalmente fecham no terminate. Se o processo ignorar o
            // SIGTERM (ou um filho herdar o pipe), um `ioGroup.wait()` sem prazo
            // prendia esta thread — e o slot do `duGate` — para sempre.
            if ioGroup.wait(timeout: .now() + Self.terminateGrace) == .timedOut {
                kill(task.processIdentifier, SIGKILL)
                // Se ainda assim não fechar (processo preso em I/O), abandona as
                // leituras em vez de bloquear o chamador.
                _ = ioGroup.wait(timeout: .now() + Self.terminateGrace)
            }
            return ("", "Command timed out after \(timeout) seconds", -1)
        }

        ioGroup.wait() // garante leitura completa da saída antes de retornar
        let output = String(data: outputData.value, encoding: .utf8) ?? ""
        let error = String(data: errorData.value, encoding: .utf8) ?? ""
        return (output, error, task.terminationStatus)
    }

    func checkCommandExists(_ command: String) -> Bool {
        let result = execute("which \(command)", timeout: 5)
        return result.exitCode == 0
    }
}
