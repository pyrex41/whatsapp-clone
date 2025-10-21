//
//  PhoenixChannelManager+CDC.swift
//  GlobalBridge
//
//  Task 13: CDC sync integration with Phoenix Channel Manager
//

import Foundation

/// Extension to PhoenixChannelManager to support CDC sync operations
extension PhoenixChannelManager: PhoenixChannelManagerProtocol {

    /// Pull CDC logs from server for a specific thread
    /// - Parameters:
    ///   - threadId: Thread ID to pull changes for
    ///   - since: Optional timestamp to fetch changes since
    /// - Returns: Array of CDC logs from server
    public func pullCDCLogs(threadId: String, since: Date?) async throws -> [CDCLog] {
        guard let channel = channels["conversation:\(threadId)"] else {
            throw PhoenixError.channelNotJoined
        }

        var payload: [String: Any] = [:]
        if let sinceDate = since {
            payload["since"] = ISO8601DateFormatter().string(from: sinceDate)
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("cdc:pull", payload: payload)
                .receive("ok") { response in
                    do {
                        // Parse CDC logs from response
                        guard let logsData = response.payload["logs"] as? [[String: Any]] else {
                            continuation.resume(returning: [])
                            return
                        }

                        let logs = try logsData.compactMap { logDict -> CDCLog? in
                            try self.parseCDCLog(from: logDict)
                        }

                        continuation.resume(returning: logs)
                    } catch {
                        continuation.resume(throwing: PhoenixError.decodingFailed(error))
                    }
                }
                .receive("error") { message in
                    continuation.resume(throwing: PhoenixError.sendFailed(message.payload))
                }
                .receive("timeout") { _ in
                    continuation.resume(throwing: PhoenixError.timeout)
                }
        }
    }

    /// Push CDC logs to server for a specific thread
    /// - Parameters:
    ///   - logs: CDC logs to push
    ///   - threadId: Thread ID these logs belong to
    public func pushCDCLogs(_ logs: [CDCLog], threadId: String) async throws {
        guard let channel = channels["conversation:\(threadId)"] else {
            throw PhoenixError.channelNotJoined
        }

        // Convert logs to serializable format
        let logsPayload = logs.map { log -> [String: Any] in
            var dict: [String: Any] = [
                "id": log.id.uuidString,
                "table_name": log.tableName,
                "record_id": log.recordId.uuidString,
                "operation": log.operation.rawValue,
                "new_data": log.newData,
                "timestamp": ISO8601DateFormatter().string(from: log.timestamp)
            ]

            if let oldData = log.oldData {
                dict["old_data"] = oldData
            }

            if let changedFields = log.changedFields {
                dict["changed_fields"] = changedFields
            }

            if let userId = log.userId {
                dict["user_id"] = userId.uuidString
            }

            if let deviceId = log.deviceId {
                dict["device_id"] = deviceId.uuidString
            }

            return dict
        }

        let payload: [String: Any] = ["logs": logsPayload]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.push("cdc:push", payload: payload)
                .receive("ok") { _ in
                    continuation.resume()
                }
                .receive("error") { message in
                    continuation.resume(throwing: PhoenixError.sendFailed(message.payload))
                }
                .receive("timeout") { _ in
                    continuation.resume(throwing: PhoenixError.timeout)
                }
        }
    }

    /// Check if network is available
    /// - Returns: True if connected, false otherwise
    public func isNetworkAvailable() -> Bool {
        switch connectionState {
        case .connected:
            return true
        default:
            return false
        }
    }

    // MARK: - Private Helpers

    /// Parse a CDC log from dictionary
    private func parseCDCLog(from dict: [String: Any]) throws -> CDCLog {
        guard let idStr = dict["id"] as? String,
              let id = UUID(uuidString: idStr),
              let tableName = dict["table_name"] as? String,
              let recordIdStr = dict["record_id"] as? String,
              let recordId = UUID(uuidString: recordIdStr),
              let operationStr = dict["operation"] as? String,
              let operation = CDCLog.CDCOperation(rawValue: operationStr),
              let newData = dict["new_data"] as? [String: String],
              let timestampStr = dict["timestamp"] as? String,
              let timestamp = ISO8601DateFormatter().date(from: timestampStr) else {
            throw PhoenixError.decodingFailed(
                NSError(domain: "CDCParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid CDC log data"])
            )
        }

        let oldData = dict["old_data"] as? [String: String]
        let changedFields = dict["changed_fields"] as? [String]

        let userId = (dict["user_id"] as? String).flatMap { UUID(uuidString: $0) }
        let deviceId = (dict["device_id"] as? String).flatMap { UUID(uuidString: $0) }

        let createdAtStr = dict["created_at"] as? String
        let createdAt = createdAtStr.flatMap { ISO8601DateFormatter().date(from: $0) } ?? timestamp

        return CDCLog(
            id: id,
            tableName: tableName,
            recordId: recordId,
            operation: operation,
            oldData: oldData,
            newData: newData,
            changedFields: changedFields,
            userId: userId,
            deviceId: deviceId,
            timestamp: timestamp,
            createdAt: createdAt
        )
    }
}
