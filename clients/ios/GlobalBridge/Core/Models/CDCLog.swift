//
//  CDCLog.swift
//  GlobalBridge
//
//  Created by DatabaseManager on 10/20/25.
//

import Foundation

/// Change Data Capture log entry for sync operations
struct CDCLog: Identifiable, Codable, Equatable {
    let id: String  // Changed from UUID - backend uses MD5 hash strings
    let tableName: String
    let recordId: UUID
    let operation: CDCOperation
    var oldData: [String: String]?
    let newData: [String: String]
    var changedFields: [String]?
    var userId: UUID?
    var deviceId: UUID?
    let timestamp: Date
    let createdAt: Date

    enum CDCOperation: String, Codable {
        case insert = "insert"
        case update = "update"
        case delete = "delete"
    }

    nonisolated init(
        id: String,  // Changed from UUID
        tableName: String,
        recordId: UUID,
        operation: CDCOperation,
        oldData: [String: String]? = nil,
        newData: [String: String],
        changedFields: [String]? = nil,
        userId: UUID? = nil,
        deviceId: UUID? = nil,
        timestamp: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.tableName = tableName
        self.recordId = recordId
        self.operation = operation
        self.oldData = oldData
        self.newData = newData
        self.changedFields = changedFields
        self.userId = userId
        self.deviceId = deviceId
        self.timestamp = timestamp
        self.createdAt = createdAt
    }
}

/// Sync state tracking for each entity
struct SyncState: Identifiable, Codable, Equatable {
    let id: UUID
    let deviceId: UUID
    var threadId: UUID?
    let entityType: String
    let entityId: UUID
    let operation: String
    var lastSyncAt: Date?
    var syncCursor: Int?
    var isSynced: Bool
    let createdAt: Date
    let updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        deviceId: UUID,
        threadId: UUID? = nil,
        entityType: String,
        entityId: UUID,
        operation: String,
        lastSyncAt: Date? = nil,
        syncCursor: Int? = nil,
        isSynced: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.deviceId = deviceId
        self.threadId = threadId
        self.entityType = entityType
        self.entityId = entityId
        self.operation = operation
        self.lastSyncAt = lastSyncAt
        self.syncCursor = syncCursor
        self.isSynced = isSynced
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
