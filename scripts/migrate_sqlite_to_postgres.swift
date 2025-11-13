#!/usr/bin/env swift

// migrate_sqlite_to_postgres.swift
// Migration script to transfer SQLite track mappings to PostgreSQL

import Foundation
import SQLite3

struct TrackMapping {
    let tempID: String
    let logicUUID: String
    let trackName: String
    let trackNumber: Int?
    let lastUpdated: String
}

class SQLiteMigration {
    private var db: OpaquePointer?
    private let sqlitePath: String

    init(sqlitePath: String) {
        self.sqlitePath = sqlitePath
    }

    func readAllMappings() -> [TrackMapping] {
        var mappings: [TrackMapping] = []

        // Open SQLite database
        guard sqlite3_open(sqlitePath, &db) == SQLITE_OK else {
            print("Error: Unable to open SQLite database at \(sqlitePath)")
            return []
        }

        defer {
            sqlite3_close(db)
        }

        let query = "SELECT temp_id, logic_uuid, track_name, track_number, last_updated FROM track_mappings"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("Error: Failed to prepare query")
            return []
        }

        defer {
            sqlite3_finalize(statement)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            let tempID = String(cString: sqlite3_column_text(statement, 0))
            let logicUUID = String(cString: sqlite3_column_text(statement, 1))
            let trackName = String(cString: sqlite3_column_text(statement, 2))
            let trackNumber = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 3))
            let lastUpdated = String(cString: sqlite3_column_text(statement, 4))

            mappings.append(TrackMapping(
                tempID: tempID,
                logicUUID: logicUUID,
                trackName: trackName,
                trackNumber: trackNumber,
                lastUpdated: lastUpdated
            ))
        }

        print("Read \(mappings.count) mappings from SQLite")
        return mappings
    }
}

struct PostgresMigration {
    let host: String
    let port: Int
    let database: String
    let username: String
    let password: String

    func generateMigrationSQL(mappings: [TrackMapping], projectName: String = "Default Project") -> String {
        var sql = """
        -- Migration script generated on \(Date())
        -- Source: SQLite track_mappings.db
        -- Target: PostgreSQL chatty_channels database

        BEGIN;

        -- Get or create project
        INSERT INTO projects (name, last_opened_at)
        VALUES ('\(projectName)', CURRENT_TIMESTAMP)
        ON CONFLICT (name) DO UPDATE SET last_opened_at = CURRENT_TIMESTAMP
        RETURNING id;

        -- Store the project_id in a variable
        DO $$
        DECLARE
            v_project_id UUID;
            v_session_id UUID;
        BEGIN
            -- Get project ID
            SELECT id INTO v_project_id FROM projects WHERE name = '\(projectName)' AND deleted_at IS NULL;

            -- Create a new session for migration
            INSERT INTO sessions (project_id, is_active)
            VALUES (v_project_id, TRUE)
            RETURNING id INTO v_session_id;

            -- Migrate track assignments

        """

        for mapping in mappings {
            let trackNumber = mapping.trackNumber ?? 0
            sql += """
                INSERT INTO track_assignments (project_id, session_id, track_number, track_name, plugin_id, is_current)
                VALUES (v_project_id, v_session_id, \(trackNumber), '\(mapping.trackName.replacingOccurrences(of: "'", with: "''"))', '\(mapping.tempID)', TRUE);

            """
        }

        sql += """
        END $$;

        COMMIT;

        -- Verify migration
        SELECT
            p.name as project_name,
            ta.track_number,
            ta.track_name,
            ta.plugin_id
        FROM track_assignments ta
        JOIN projects p ON ta.project_id = p.id
        WHERE p.name = '\(projectName)' AND ta.is_current = TRUE
        ORDER BY ta.track_number;
        """

        return sql
    }
}

// MARK: - Main Migration

print("=== Chatty Channels SQLite to PostgreSQL Migration ===\n")

// Default SQLite path
let homeDir = FileManager.default.homeDirectoryForCurrentUser
let sqlitePath = homeDir
    .appendingPathComponent("Library/Application Support/ChattyChannels/track_mappings.db")
    .path

print("SQLite database path: \(sqlitePath)")

// Check if SQLite database exists
guard FileManager.default.fileExists(atPath: sqlitePath) else {
    print("Error: SQLite database not found at \(sqlitePath)")
    print("No migration needed - starting fresh with PostgreSQL")
    exit(0)
}

// Read SQLite data
let sqliteMigration = SQLiteMigration(sqlitePath: sqlitePath)
let mappings = sqliteMigration.readAllMappings()

if mappings.isEmpty {
    print("No mappings found in SQLite database")
    print("No migration needed - starting fresh with PostgreSQL")
    exit(0)
}

// Generate PostgreSQL migration SQL
let postgresMigration = PostgresMigration(
    host: "localhost",
    port: 5432,
    database: "chatty_channels",
    username: "postgres",
    password: ""
)

let projectName = "Migrated Project"
let migrationSQL = postgresMigration.generateMigrationSQL(mappings: mappings, projectName: projectName)

// Output migration SQL
let outputPath = homeDir.appendingPathComponent("chatty_channels_migration.sql").path
do {
    try migrationSQL.write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("\n✓ Migration SQL generated successfully!")
    print("Output file: \(outputPath)")
    print("\nTo apply the migration, run:")
    print("psql -U postgres -d chatty_channels -f \(outputPath)")
    print("\nOr if using Docker:")
    print("docker exec -i chatty-channels-db psql -U postgres -d chatty_channels < \(outputPath)")
} catch {
    print("Error writing migration file: \(error)")
    exit(1)
}

print("\n=== Migration Complete ===")
