//
//  DatabaseError.swift
//  GlobalBridge
//
//  Created by DatabaseManager on 10/20/25.
//

import Foundation

/// Errors that can occur during database operations
enum DatabaseError: Error, LocalizedError {
    case initializationFailed(String)
    case connectionFailed(String)
    case queryFailed(String)
    case insertFailed(String)
    case updateFailed(String)
    case deleteFailed(String)
    case notFound(String)
    case invalidData(String)
    case migrationFailed(String)
    case shardingFailed(String)
    case transactionFailed(String)

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return "Database initialization failed: \(message)"
        case .connectionFailed(let message):
            return "Database connection failed: \(message)"
        case .queryFailed(let message):
            return "Query execution failed: \(message)"
        case .insertFailed(let message):
            return "Insert operation failed: \(message)"
        case .updateFailed(let message):
            return "Update operation failed: \(message)"
        case .deleteFailed(let message):
            return "Delete operation failed: \(message)"
        case .notFound(let message):
            return "Record not found: \(message)"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .migrationFailed(let message):
            return "Migration failed: \(message)"
        case .shardingFailed(let message):
            return "Database sharding failed: \(message)"
        case .transactionFailed(let message):
            return "Transaction failed: \(message)"
        }
    }
}
