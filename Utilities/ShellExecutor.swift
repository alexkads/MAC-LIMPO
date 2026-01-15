import Foundation

class ShellExecutor {
    static let shared = ShellExecutor()
    
    @discardableResult
    func execute(_ command: String, requiresSudo: Bool = false, timeout: TimeInterval = 60) -> (output: String, error: String, exitCode: Int32) {
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
        
        do {
            try task.run()
            
            // Implementa timeout
            let deadline = Date().addingTimeInterval(timeout)
            while task.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            // Se ainda estiver rodando após timeout, termina o processo
            if task.isRunning {
                task.terminate()
                return ("", "Command timed out after \(timeout) seconds", -1)
            }
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            return (output, error, task.terminationStatus)
        } catch {
            return ("", error.localizedDescription, -1)
        }
    }
    
    func checkCommandExists(_ command: String) -> Bool {
        let result = execute("which \(command)", timeout: 5)
        return result.exitCode == 0
    }
}
