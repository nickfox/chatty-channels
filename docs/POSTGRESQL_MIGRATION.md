# PostgreSQL Migration Guide

This document describes the migration from SQLite to PostgreSQL for Chatty Channels.

## Overview

The migration replaces the SQLite database with a full PostgreSQL database that includes:

- **Multi-project support**: Track multiple Logic Pro projects
- **Session management**: Separate sessions within each project
- **Conversation history**: Store all LLM conversations with embeddings
- **Mission Control**: Debug and conversation tracking for orchestrator
- **Vector embeddings**: Semantic search using nomic-embed-text (via Ollama)

## Prerequisites

### 1. PostgreSQL with pgvector

Choose one option:

#### Option A: Docker (Recommended)

```bash
cd database
docker-compose up -d
```

#### Option B: Local Installation

```bash
# macOS with Homebrew
brew install postgresql@16 pgvector
brew services start postgresql@16

# Create database
createdb chatty_channels

# Initialize schema
psql -d chatty_channels -f database/schema.sql
```

### 2. Ollama (for embeddings)

```bash
# Install Ollama
brew install ollama

# Start service
ollama serve

# Pull model
ollama pull nomic-embed-text:latest
```

## Swift Package Dependencies

### Add to Xcode Project

1. Open `ChattyChannels.xcodeproj` in Xcode
2. Select the project in the navigator
3. Select the `ChattyChannels` target
4. Go to "General" → "Frameworks, Libraries, and Embedded Content"
5. Click the `+` button under "Frameworks, Libraries, and Embedded Content"
6. Click "Add Other..." → "Add Package Dependency..."
7. Add the following packages:

#### PostgresNIO

- **URL**: `https://github.com/vapor/postgres-nio.git`
- **Version**: `1.21.0` or later
- **Products**: `PostgresNIO`

#### PostgresKit (optional, for higher-level API)

- **URL**: `https://github.com/vapor/postgres-kit.git`
- **Version**: `2.12.0` or later
- **Products**: `PostgresKit`

### Verify Installation

After adding the packages, build the project:

```bash
cd ChattyChannels
xcodebuild -scheme ChattyChannels -configuration Debug build
```

If you see errors about missing modules, make sure to:

1. Clean build folder (Cmd+Shift+K)
2. Clean derived data
3. Restart Xcode

## Migration Steps

### 1. Migrate Existing Data (Optional)

If you have existing SQLite data:

```bash
# Run migration script
swift scripts/migrate_sqlite_to_postgres.swift

# This generates: ~/chatty_channels_migration.sql

# Apply migration
psql -U postgres -d chatty_channels -f ~/chatty_channels_migration.sql

# Or with Docker:
docker exec -i chatty-channels-db psql -U postgres -d chatty_channels < ~/chatty_channels_migration.sql
```

### 2. Update Database Configuration

The database is automatically initialized in `ChattyChannelsApp.swift`:

```swift
// Initialize PostgreSQL database
try await DatabaseConfiguration.shared.initialize()

// Setup project context
try await DatabaseConfiguration.shared.setupProject(
    name: "MySong.logicx",
    logicProjectPath: "/path/to/MySong.logicx"
)
```

You can customize the connection settings:

```swift
try await DatabaseConfiguration.shared.initialize(
    host: "localhost",
    port: 5432,
    database: "chatty_channels",
    username: "postgres",
    password: "your_password"
)
```

### 3. Update Service Usage

#### Track Mapping Service

The `TrackMappingService` now uses async/await:

```swift
// Old (SQLite)
let mappings = try trackMappingService.loadMapping()

// New (PostgreSQL)
let mappings = try await trackMappingService.loadMapping()
```

#### Conversation Storage

New service for storing LLM conversations:

```swift
let convService = ConversationStorageService()

// Save user message
let messageID = try await convService.saveMessage(
    role: "user",
    content: "Increase the bass on track 1",
    model: "claude-sonnet-4-5",
    generateEmbedding: true
)

// Save assistant response with key decision flag
try await convService.saveMessage(
    role: "assistant",
    content: "I've increased the bass on track 1 by 3dB",
    model: "claude-sonnet-4-5",
    isKeyDecision: true,
    decisionSummary: "Increased bass by 3dB on track 1"
)

// Get recent conversation history
let recentMessages = try await convService.getRecentMessages(limit: 10)
```

#### Mission Control Logging

```swift
let convService = ConversationStorageService()

// Log producer-user conversation
try await convService.saveMissionControlConversation(
    role: "producer",
    content: "The mix sounds great!",
    displayType: "chat"
)

// Log agent debug messages
try await convService.saveMissionControlDebug(
    sender: "orchestrator",
    receiver: "osc_agent",
    messageType: "command",
    content: "Request track assignments",
    payload: "{\"command\":\"get_assignments\"}",
    severity: "info"
)
```

## Schema Overview

### Core Tables

| Table | Description |
|-------|-------------|
| `projects` | Logic Pro project metadata |
| `sessions` | Working sessions within projects |
| `messages` | User and LLM conversation messages with embeddings |
| `track_assignments` | Current track-to-plugin mappings |

### Mission Control Tables

| Table | Description |
|-------|-------------|
| `mission_control_conversations` | Producer-user chat log (user-facing) |
| `mission_control_debug` | Agent-orchestrator debug messages (developer view) |

### Supporting Tables

| Table | Description |
|-------|-------------|
| `context_snapshots` | Snapshots of important project moments |

## API Changes

### TrackMappingService

| Method | Old (SQLite) | New (PostgreSQL) |
|--------|-------------|------------------|
| `loadMapping()` | `throws -> [String: String]` | `async throws -> [String: String]` |
| `getTrackByID(_:)` | `(String) -> (name: String, uuid: String)?` | `async throws (String) -> (name: String, uuid: String)?` |
| `clearMappings()` | `() -> Void` | `async throws -> Void` |

### Database Direct Access

For advanced use cases, you can access the PostgreSQL database directly:

```swift
guard let database = DatabaseConfiguration.shared.database else {
    throw DatabaseError.notConnected
}

guard let context = DatabaseConfiguration.shared.getCurrentContext() else {
    throw DatabaseError.notConfigured
}

// Save track assignment
try await database.saveTrackAssignment(
    projectID: context.projectID,
    sessionID: context.sessionID,
    trackNumber: 1,
    trackName: "Kick",
    pluginID: "TR1"
)

// Get track assignments
let assignments = try await database.getAllTrackAssignments(
    projectID: context.projectID,
    sessionID: context.sessionID
)
```

## Testing

### 1. Database Connection

```swift
// Test database connection
let dbConfig = DatabaseConfiguration.shared
try await dbConfig.initialize()
print("✓ Database connected successfully")
```

### 2. Track Mapping

```swift
// Test track mapping storage
let trackService = TrackMappingService()
let mappings = try await trackService.loadMapping()
print("✓ Track mappings loaded: \(mappings.count) tracks")
```

### 3. Conversation Storage

```swift
// Test conversation storage
let convService = ConversationStorageService()
let messageID = try await convService.saveMessage(
    role: "user",
    content: "Test message",
    generateEmbedding: true
)
print("✓ Message saved with ID: \(messageID)")
```

### 4. Embeddings

```swift
// Test embedding generation
let embeddingService = EmbeddingService()
let isAvailable = await embeddingService.checkAvailability()
print("✓ Embedding service available: \(isAvailable)")

if isAvailable {
    let embedding = try await embeddingService.generateEmbedding(for: "Test text")
    print("✓ Generated \(embedding.count)-dimensional embedding")
}
```

## Troubleshooting

### Database Connection Issues

```bash
# Check PostgreSQL is running
docker ps | grep chatty-channels-db
# or
brew services list | grep postgresql

# Test connection manually
psql -h localhost -U postgres -d chatty_channels

# Check logs
docker logs chatty-channels-db
```

### Swift Package Issues

```bash
# Reset package cache
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf .build

# In Xcode:
# File → Packages → Reset Package Caches
# File → Packages → Update to Latest Package Versions
```

### Embedding Service Not Available

```bash
# Check Ollama is running
ollama list

# Check if model is downloaded
ollama pull nomic-embed-text:latest

# Test manually
curl http://localhost:11434/api/embeddings -d '{
  "model": "nomic-embed-text",
  "prompt": "test"
}'
```

## Rollback to SQLite

If you need to rollback to SQLite temporarily:

1. The old `SQLiteDatabase.swift` can be kept as backup
2. Revert `TrackMappingService.swift` to use SQLite
3. Remove database initialization from `ChattyChannelsApp.swift`

However, note that **no backward compatibility is maintained** - the PostgreSQL migration is one-way.

## Performance Considerations

- **Connection Pooling**: Consider implementing connection pooling for production
- **Indexes**: The schema includes optimized indexes for common queries
- **Vector Search**: HNSW index is used for fast approximate nearest neighbor search
- **Batch Operations**: Use batch inserts for bulk data

## Security Considerations

For production:

1. **Change default passwords**
2. **Use SSL/TLS connections**
3. **Implement row-level security (RLS)**
4. **Regular backups**
5. **Monitor database logs**

## Next Steps

After migration:

1. ✅ Add conversation storage to LLM integration
2. ✅ Implement Mission Control UI with debug view
3. ✅ Add semantic search for context retrieval
4. ✅ Implement context snapshots for important moments
5. ✅ Add analytics and usage tracking

## Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [PostgresNIO Documentation](https://github.com/vapor/postgres-nio)
- [Ollama Documentation](https://ollama.ai/docs)
