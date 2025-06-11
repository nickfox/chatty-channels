// SQLiteDatabase.swift
// Database helper for persisting track mappings

import Foundation
import SQLite3
import OSLog

/// SQLite database wrapper for track mapping persistence
public class SQLiteDatabase {
    private var db: OpaquePointer?
    private let dbPath: String
    private let logger = Logger(subsystem: "com.websmithing.ChattyChannels", category: "SQLiteDatabase")
    
    // Table and column names
    private let tableName = "track_mappings"
    private let colTempID = "temp_id"
    private let colLogicUUID = "logic_uuid"
    private let colTrackName = "track_name"
    private let colTrackNumber = "track_number"
    private let colLastUpdated = "last_updated"
    
    public init(dbPath: String? = nil) {
        if let path = dbPath {
            self.dbPath = path
        } else {
            // Default to app support directory
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDir = appSupport.appendingPathComponent("ChattyChannels", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            self.dbPath = appDir.appendingPathComponent("track_mappings.db").path
        }
        
        openDatabase()
        createTables()
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - Database Operations
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            logger.error("Unable to open database at \(self.dbPath)")
            db = nil
        } else {
            logger.info("Successfully opened database at \(self.dbPath)")
        }
    }
    
    private func closeDatabase() {
        if sqlite3_close(db) != SQLITE_OK {
            logger.error("Error closing database")
        }
        db = nil
    }
    
    private func createTables() {
        let createTableString = """
            CREATE TABLE IF NOT EXISTS \(tableName) (
                \(colTempID) TEXT PRIMARY KEY,
                \(colLogicUUID) TEXT NOT NULL,
                \(colTrackName) TEXT NOT NULL,
                \(colTrackNumber) INTEGER,
                \(colLastUpdated) TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            CREATE INDEX IF NOT EXISTS idx_logic_uuid ON \(tableName)(\(colLogicUUID));
            CREATE INDEX IF NOT EXISTS idx_track_name ON \(tableName)(\(colTrackName));
        """
        
        var createTableStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, createTableString, -1, &createTableStatement, nil) == SQLITE_OK {
            if sqlite3_step(createTableStatement) == SQLITE_DONE {
                logger.info("Track mappings table created successfully")
            } else {
                logger.error("Track mappings table could not be created")
            }
        } else {
            logger.error("CREATE TABLE statement could not be prepared")
        }
        sqlite3_finalize(createTableStatement)
    }
    
    // MARK: - Public API
    
    /// Insert or update a track mapping
    public func saveTrackMapping(tempID: String, logicUUID: String, trackName: String, trackNumber: Int? = nil) -> Bool {
        let insertSQL = """
            INSERT OR REPLACE INTO \(tableName) 
            (\(colTempID), \(colLogicUUID), \(colTrackName), \(colTrackNumber), \(colLastUpdated))
            VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
        """
        
        var insertStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil) == SQLITE_OK {
            // Use NSString to ensure the strings persist for SQLite
            let nsTempID = tempID as NSString
            let nsLogicUUID = logicUUID as NSString
            let nsTrackName = trackName as NSString
            
            sqlite3_bind_text(insertStatement, 1, nsTempID.utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, nsLogicUUID.utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 3, nsTrackName.utf8String, -1, nil)
            
            if let trackNum = trackNumber {
                sqlite3_bind_int(insertStatement, 4, Int32(trackNum))
            } else {
                sqlite3_bind_null(insertStatement, 4)
            }
            
            if sqlite3_step(insertStatement) == SQLITE_DONE {
                logger.info("Successfully saved mapping: \(tempID) -> \(trackName)")
                sqlite3_finalize(insertStatement)
                return true
            } else {
                logger.error("Could not save track mapping")
            }
        } else {
            logger.error("INSERT statement could not be prepared")
        }
        
        sqlite3_finalize(insertStatement)
        return false
    }
    
    /// Get all track mappings as a dictionary [trackName: logicUUID]
    public func getAllTrackMappings() -> [String: String] {
        let querySQL = "SELECT \(colTrackName), \(colLogicUUID) FROM \(tableName)"
        var queryStatement: OpaquePointer?
        var mappings: [String: String] = [:]
        
        if sqlite3_prepare_v2(db, querySQL, -1, &queryStatement, nil) == SQLITE_OK {
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                if let trackName = sqlite3_column_text(queryStatement, 0),
                   let logicUUID = sqlite3_column_text(queryStatement, 1) {
                    let name = String(cString: trackName)
                    let uuid = String(cString: logicUUID)
                    mappings[name] = uuid
                }
            }
        } else {
            logger.error("SELECT statement could not be prepared")
        }
        
        sqlite3_finalize(queryStatement)
        return mappings
    }
    
    /// Get mapping by temporary ID
    public func getMappingByTempID(_ tempID: String) -> (logicUUID: String, trackName: String)? {
        let querySQL = "SELECT \(colLogicUUID), \(colTrackName) FROM \(tableName) WHERE \(colTempID) = ?"
        var queryStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, querySQL, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(queryStatement, 1, tempID, -1, nil)
            
            if sqlite3_step(queryStatement) == SQLITE_ROW {
                if let logicUUID = sqlite3_column_text(queryStatement, 0),
                   let trackName = sqlite3_column_text(queryStatement, 1) {
                    let uuid = String(cString: logicUUID)
                    let name = String(cString: trackName)
                    sqlite3_finalize(queryStatement)
                    return (logicUUID: uuid, trackName: name)
                }
            }
        }
        
        sqlite3_finalize(queryStatement)
        return nil
    }
    
    /// Clear all mappings
    public func clearAllMappings() -> Bool {
        let deleteSQL = "DELETE FROM \(tableName)"
        var deleteStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK {
            if sqlite3_step(deleteStatement) == SQLITE_DONE {
                logger.info("All track mappings cleared")
                sqlite3_finalize(deleteStatement)
                return true
            }
        }
        
        sqlite3_finalize(deleteStatement)
        return false
    }
    
    /// Get mappings updated after a certain date
    public func getMappingsUpdatedAfter(date: Date) -> [(tempID: String, logicUUID: String, trackName: String)] {
        let querySQL = """
            SELECT \(colTempID), \(colLogicUUID), \(colTrackName) 
            FROM \(tableName) 
            WHERE \(colLastUpdated) > ?
            ORDER BY \(colLastUpdated) DESC
        """
        
        var queryStatement: OpaquePointer?
        var results: [(tempID: String, logicUUID: String, trackName: String)] = []
        
        if sqlite3_prepare_v2(db, querySQL, -1, &queryStatement, nil) == SQLITE_OK {
            let timestamp = date.timeIntervalSince1970
            sqlite3_bind_double(queryStatement, 1, timestamp)
            
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                if let tempID = sqlite3_column_text(queryStatement, 0),
                   let logicUUID = sqlite3_column_text(queryStatement, 1),
                   let trackName = sqlite3_column_text(queryStatement, 2) {
                    results.append((
                        tempID: String(cString: tempID),
                        logicUUID: String(cString: logicUUID),
                        trackName: String(cString: trackName)
                    ))
                }
            }
        }
        
        sqlite3_finalize(queryStatement)
        return results
    }
}
