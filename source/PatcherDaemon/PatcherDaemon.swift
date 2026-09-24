/*
    PatcherDaemon.swift
    Copyright 2026 SAP SE
     
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
     
    http://www.apache.org/licenses/LICENSE-2.0
     
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

import Foundation
import CryptoKit
import OSLog

class PatcherDaemon: NSObject, PatcherDaemonProtocol
{
    var listenerEndpoint: NSXPCListenerEndpoint!
    var shouldTerminate: Bool = false
    
    private var installationProgressByIdentifier: [String: Float] = [:]
    private var installDelegate: (any MTInstallDelegate)?
    
    private let errorDomain = "corp.sap.PatcherDaemon"
    private let installationQueue = AsyncSemaphore(value: 1)
    
    // MARK: - PatcherDaemonProtocol
    
    func connect(endpointReply: @escaping (NSXPCListenerEndpoint) -> Void)
    {
        endpointReply(listenerEndpoint)
    }
    
    func availableApplications(reply: @escaping ([MTApplication], NSError?) -> Void) {
        
        Task {
            
            do {
                let allApplications = try await MTApplicationRepository.shared.availableApplications()

                for application in allApplications {
                    
                    if let progress = installationProgressByIdentifier[application.identifier] {
                        application.isInstalling = true
                        application.installProgress = progress
                    } else {
                        application.isInstalling = false
                        application.installProgress = 0
                    }
                }

                reply(allApplications, nil)
                
            } catch {
                
                reply([], xpcSafeError(from: error))
            }
        }
    }
    
    func registerInstallDelegate(reply: @escaping (_ success: Bool) -> Void)
    {
        installDelegate = NSXPCConnection.current()?.remoteObjectProxy as? any MTInstallDelegate
        reply(installDelegate != nil)
    }
    
    func installApplicationWithIdentifier(_ identifier: String, reply: @escaping (_ error: NSError?) -> Void)
    {
        Task {
            
            do {
                
                let allApplications = try await MTApplicationRepository.shared.availableApplications()
                
                guard let application = allApplications.first(where: { $0.identifier == identifier }) else {
                    
                    throw makeError(
                        code: 1001,
                        description: "Unknown application identifier: \(identifier)"
                    )
                }
                
                installationIsQueued(for: application)
                
                try await installationQueue.withPermit {
                    
                    try await installApplication(application: application)
                }
                
                reply(nil)
                
            } catch {
                
                reply(xpcSafeError(from: error))
            }
        }
    }
    
    func refreshInstalledStateForApplicationWithIdentifier(_ identifier: String, reply: @escaping (_ application: MTApplication?, _ error: NSError?) -> Void) {
        
        Task {
            
            do {
                
                _ = try await MTApplicationRepository.shared.availableApplications()
                
                guard let application = await MTApplicationRepository.shared.refreshInstalledState(forIdentifier: identifier) else {
                    
                    throw makeError(
                        code: 1401,
                        description: "Unknown application identifier: \(identifier)"
                    )
                }
                                
                reply(application, nil)
                
            } catch {
                
                reply(nil, xpcSafeError(from: error))
            }
        }
    }
    
    // MARK: - private
    
    private func installApplication(application: MTApplication) async throws
    {
        installationDidStart(for: application)
        
        do {
            
            guard let downloadURL = URL(string: application.downloadURL) else {
                throw makeError(
                    code: 1002,
                    description: "No valid download URL found for application: \(application.name)"
                )
            }
            
            try validateDownloadURL(downloadURL)
            
            Logger().log("SAPCorp: Downloading \(application.name, privacy: .public) from \(downloadURL.absoluteString, privacy: .public)")
            
            let packageURL = try await downloadPackage(from: downloadURL, for: application)
            
            defer {
                
                try? FileManager.default.removeItem(at: packageURL.deletingLastPathComponent())
            }
            
            try await validatePackage(at: packageURL, for: application)
            try await installPackage(at: packageURL)
            
            _ = await MTApplicationRepository.shared.refreshInstalledState(forIdentifier: application.identifier)
            
            installationDidFinish(for: application)
            
        } catch {
            
            installationDidFail(for: application, withError: error)
            throw error
        }
    }
    
    private func validateDownloadURL(_ url: URL) throws
    {
        guard url.scheme?.lowercased() == "https" else {
            
            throw makeError(
                code: 1101,
                description: "Download URL must use HTTPS: \(url.absoluteString)"
            )
        }
        
        guard url.pathExtension.lowercased() == "pkg" else {
            
            throw makeError(
                code: 1102,
                description: "Download URL does not point to a PKG file: \(url.absoluteString)"
            )
        }
    }
    
    private func downloadPackage(from url: URL, for application: MTApplication) async throws -> URL
    {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("corp.sap.PatcherDaemon", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        
        let destinationURL = temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        
        installationProgress(for: application, didUpdate: 0)
        
        let delegate = PackageDownloadDelegate(
            destinationURL: destinationURL,
            errorDomain: errorDomain
        ) { [weak self] progress in
            
            self?.installationProgress(for: application, didUpdate: progress)
        }
        
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        
        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        
        defer {
            
            session.finishTasksAndInvalidate()
        }
        
        do {
            
            return try await withCheckedThrowingContinuation { continuation in
                
                delegate.setContinuation(continuation)
                
                let task = session.downloadTask(with: request)
                task.resume()
            }
            
        } catch {
            
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }
    
    private func validatePackage(at packageURL: URL, for application: MTApplication) async throws
    {
        // MARK: - Check pkg checksum
        
        let handle = try FileHandle(forReadingFrom: packageURL)
        defer { try? handle.close() }

        var hasher = SHA256()

        while true {
                
            let chunk = try handle.read(upToCount: 1024 * 1024)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        
        let calculatedChecksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        
        guard application.sha256Checksum.lowercased() == calculatedChecksum else {
            
            throw makeError(
                code: 1200,
                description: "Package checksum validation failed for application: \(application.name)"
            )
        }
        
        // MARK: - Check pkg signing
        
        let spctlResult = try await runProcess(
            executablePath: "/usr/sbin/spctl",
            arguments: [
                "-a",
                "-vv",
                "-t",
                "install",
                packageURL.path
            ]
        )
        
        let isCorrectOrigin = spctlResult.output
            .split(separator: "\n")
            .contains { $0 == "origin=\(kMTPackageSignature)" }
        
        guard spctlResult.terminationStatus == 0 && isCorrectOrigin else {
            
            throw makeError(
                code: 1201,
                description: "Package assessment failed: \(spctlResult.output)"
            )
        }

        // MARK: - Check if signing cert has expired
        
        let pkgutilResult = try await runProcess(
            executablePath: "/usr/sbin/pkgutil",
            arguments: [
                "--check-signature",
                packageURL.path
            ]
        )
        
        let isExpiredSignature = pkgutilResult.output.range(of: "Status:.*expired", options: .regularExpression) != nil
        
        guard pkgutilResult.terminationStatus == 0 && !isExpiredSignature else {
            
            throw makeError(
                code: 1202,
                description: "Package signature check failed: \(pkgutilResult.output)"
            )
        }
    }
    
    private func installPackage(at packageURL: URL) async throws
    {
        let result = try await runProcess(
            executablePath: "/usr/sbin/installer",
            arguments: [
                "-pkg",
                packageURL.path,
                "-target",
                "/"
            ]
        )
        
        guard result.terminationStatus == 0 else {
            
            throw makeError(
                code: 1301,
                description: "Installer failed: \(result.output)"
            )
        }
    }
    
    private func runProcess(executablePath: String, arguments: [String]) async throws -> ProcessResult
    {
        try await withCheckedThrowingContinuation { continuation in
            
            let process = Process()
            let outputPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            process.terminationHandler = { process in
                
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                continuation.resume(
                    returning: ProcessResult(
                        terminationStatus: process.terminationStatus,
                        output: output
                    )
                )
            }
            
            do {
                
                try process.run()
                
            } catch {
                
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func makeError(code: Int, description: String) -> NSError
    {
        NSError(
            domain: errorDomain,
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: description
            ]
        )
    }
    
    private func xpcSafeError(from error: any Error) -> NSError
    {
        let nsError = error as NSError

        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: nsError.localizedDescription
        ]

        if let failureReason = nsError.localizedFailureReason {
            userInfo[NSLocalizedFailureReasonErrorKey] = failureReason
        }

        if let recoverySuggestion = nsError.localizedRecoverySuggestion {
            userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
        }

        return NSError(
            domain: nsError.domain,
            code: nsError.code,
            userInfo: userInfo
        )
    }
    
    private static var userAgent: String {
        let bundle = Bundle.main
        
        let appName =
            (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "PatcherDaemon"
        
        let appVersion =
            (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "0"
        
        return "\(appName)/\(appVersion)"
    }
    
    private struct ProcessResult {
        
        let terminationStatus: Int32
        let output: String
    }
    
    // MARK: - MTInstallDelegate
    
    private func installationIsQueued(for application: MTApplication)
    {
        application.isInstalling = true
        installationProgressByIdentifier[application.identifier] = 0
        
        installDelegate?.installationIsQueued(for: application)
    }
    
    private func installationDidStart(for application: MTApplication)
    {
        Logger().log("SAPCorp: Installation of \(application.name, privacy: .public) (\(application.latestVersion as NSObject?, privacy: .public)) did start")
        
        application.isInstalling = true
        installationProgressByIdentifier[application.identifier] = 0

        installDelegate?.installationDidStart(for: application)
    }
    
    private func installationDidFinish(for application: MTApplication)
    {
        Logger().log("SAPCorp: Installation of \(application.name, privacy: .public) (\(application.latestVersion as NSObject?, privacy: .public)) did finish successfully")
        
        application.isInstalling = false
        installationProgressByIdentifier.removeValue(forKey: application.identifier)
        
        installDelegate?.installationDidFinish(for: application)
    }
    
    private func installationDidFail(for application: MTApplication, withError error: any Error)
    {
        Logger().error("SAPCorp: Installation of \(application.name, privacy: .public) (\(application.latestVersion as NSObject?, privacy: .public)) did fail: \(String(describing: error), privacy: .public)")
        
        application.isInstalling = false
        installationProgressByIdentifier.removeValue(forKey: application.identifier)
        
        let safeError = xpcSafeError(from: error)
        installDelegate?.installationDidFail(for: application, withError: safeError)
    }
    
    private func installationProgress(for application: MTApplication, didUpdate progress: Float)
    {
        installationProgressByIdentifier[application.identifier] = progress
        installDelegate?.installationProgress(for: application, didUpdate: progress)
    }
}

// MARK: - Download Delegate

private final class PackageDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    
    private let destinationURL: URL
    private let errorDomain: String
    private let progressHandler: (Float) -> Void
    
    private var continuation: CheckedContinuation<URL, Error>?
    private var lastReportedProgress: Float = -1
    
    init(
        destinationURL: URL,
        errorDomain: String,
        progressHandler: @escaping (Float) -> Void
    ) {
        self.destinationURL = destinationURL
        self.errorDomain = errorDomain
        self.progressHandler = progressHandler
    }
    
    func setContinuation(_ continuation: CheckedContinuation<URL, Error>)
    {
        self.continuation = continuation
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            return
        }
        
        let progress = Float(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        reportProgress(progress)
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            
            finish(
                throwing: NSError(
                    domain: errorDomain,
                    code: httpResponse.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Download failed with error \(httpResponse.statusCode)"
                    ]
                )
            )
            
            return
        }
        
        do {
            
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            reportProgress(1)
            finish(returning: destinationURL)
            
        } catch {
            
            finish(throwing: error)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?)
    {
        guard let error else { return }
        finish(throwing: error)
    }
    
    private func reportProgress(_ progress: Float)
    {
        let boundedProgress = min(max(progress, 0), 1)
        
        guard boundedProgress == 1 || boundedProgress - lastReportedProgress >= 0.01 else {
            return
        }
        
        lastReportedProgress = boundedProgress
        progressHandler(boundedProgress)
    }
    
    private func finish(returning url: URL)
    {
        guard let continuation else {
            return
        }
        
        self.continuation = nil
        continuation.resume(returning: url)
    }
    
    private func finish(throwing error: any Error)
    {
        guard let continuation else {
            return
        }
        
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

// MARK: - Async Semaphore

private actor AsyncSemaphore {
    
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(value: Int)
    {
        self.availablePermits = value
    }
    
    func withPermit<T>(_ operation: () async throws -> T) async throws -> T
    {
        await wait()
        
        defer {
            signal()
        }
        
        return try await operation()
    }
    
    private func wait() async
    {
        if availablePermits > 0 {
            
            availablePermits -= 1
            return
        }
        
        await withCheckedContinuation { continuation in
            
            waiters.append(continuation)
        }
    }
    
    private func signal()
    {
        if waiters.isEmpty {
            
            availablePermits += 1
            
        } else {
            
            let continuation = waiters.removeFirst()
            continuation.resume()
        }
    }
}
