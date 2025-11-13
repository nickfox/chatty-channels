# PostgreSQL Database Setup for Chatty Channels

This directory contains the PostgreSQL database schema and setup scripts for Chatty Channels.

## Quick Start

### Option 1: Docker (Recommended)

The easiest way to run PostgreSQL with pgvector extension:

```bash
# Start PostgreSQL with Docker Compose
cd database
docker-compose up -d

# Verify it's running
docker ps | grep chatty-channels-db

# Check logs
docker logs chatty-channels-db

# Connect to database
docker exec -it chatty-channels-db psql -U postgres -d chatty_channels
```

The schema will be automatically initialized on first run.

### Option 2: Local PostgreSQL Installation

If you prefer to install PostgreSQL locally:

```bash
# macOS with Homebrew
brew install postgresql@16
brew install pgvector

# Start PostgreSQL service
brew services start postgresql@16

# Create database
createdb chatty_channels

# Initialize schema
psql -d chatty_channels -f schema.sql
```

## Database Configuration

### Default Connection Settings

- **Host**: `localhost`
- **Port**: `5432`
- **Database**: `chatty_channels`
- **Username**: `postgres`
- **Password**: `postgres` (Docker) or empty (local)

### Custom Configuration

You can customize the database connection in your Swift code:

```swift
import ChattyChannels

// Initialize with custom settings
let dbConfig = DatabaseConfiguration.shared
try await dbConfig.initialize(
    host: "localhost",
    port: 5432,
    database: "chatty_channels",
    username: "postgres",
    password: "your_password"
)
```

## Schema Overview

The database schema includes the following tables:

### Core Tables

- **projects**: Logic Pro project metadata
- **sessions**: Working sessions within projects
- **messages**: User and LLM conversation messages with vector embeddings
- **track_assignments**: Current track-to-plugin mappings

### Mission Control Tables

- **mission_control_conversations**: Producer-user chat log (user-facing)
- **mission_control_debug**: Agent-orchestrator debug messages (developer view)

### Supporting Tables

- **context_snapshots**: Snapshots of important project moments

## Migration from SQLite

If you have existing SQLite data, use the migration script:

```bash
# Run the Swift migration script
cd scripts
swift migrate_sqlite_to_postgres.swift

# This will generate: ~/chatty_channels_migration.sql

# Apply the migration
psql -U postgres -d chatty_channels -f ~/chatty_channels_migration.sql

# Or with Docker:
docker exec -i chatty-channels-db psql -U postgres -d chatty_channels < ~/chatty_channels_migration.sql
```

## Vector Embeddings

The database uses pgvector for semantic search capabilities:

- **Embedding Model**: nomic-embed-text (via Ollama)
- **Vector Dimensions**: 768
- **Similarity Search**: Cosine similarity

### Setup Ollama for Embeddings

```bash
# Install Ollama (macOS)
brew install ollama

# Start Ollama service
ollama serve

# Pull nomic-embed-text model
ollama pull nomic-embed-text:latest

# Verify installation
ollama list
```

## Database Maintenance

### Backup

```bash
# Backup entire database
pg_dump -U postgres chatty_channels > backup_$(date +%Y%m%d).sql

# Or with Docker:
docker exec chatty-channels-db pg_dump -U postgres chatty_channels > backup_$(date +%Y%m%d).sql
```

### Restore

```bash
# Restore from backup
psql -U postgres chatty_channels < backup_20250113.sql

# Or with Docker:
docker exec -i chatty-channels-db psql -U postgres -d chatty_channels < backup_20250113.sql
```

### Reset Database

```bash
# Drop and recreate (WARNING: destroys all data)
dropdb chatty_channels
createdb chatty_channels
psql -d chatty_channels -f schema.sql

# Or with Docker:
docker-compose down -v
docker-compose up -d
```

## Common Queries

### View Active Sessions

```sql
SELECT * FROM active_sessions;
```

### View Current Track Assignments

```sql
SELECT * FROM current_track_assignments ORDER BY track_number;
```

### Search Messages by Similarity

```sql
-- Find messages similar to a query (requires embedding vector)
SELECT id, content, role, created_at
FROM messages
WHERE project_id = 'your-project-id'
ORDER BY embedding <=> 'your-query-embedding'::vector
LIMIT 10;
```

### View Mission Control Activity

```sql
SELECT * FROM mission_control_complete
ORDER BY created_at DESC
LIMIT 50;
```

## Troubleshooting

### Connection Refused

```bash
# Check if PostgreSQL is running
docker ps | grep chatty-channels-db

# Or for local installation:
brew services list | grep postgresql

# Restart service
docker-compose restart
# or
brew services restart postgresql@16
```

### pgvector Extension Not Found

```bash
# Install pgvector (local installation)
brew install pgvector

# Enable in database
psql -d chatty_channels -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

### Permission Denied

```bash
# Grant permissions (if needed)
psql -U postgres -d chatty_channels -c "GRANT ALL PRIVILEGES ON DATABASE chatty_channels TO postgres;"
```

## Development

### Connecting from Swift

```swift
// In your app initialization
let dbConfig = DatabaseConfiguration.shared
try await dbConfig.initialize()

// Set up project context
try await dbConfig.setupProject(
    name: "MySong.logicx",
    logicProjectPath: "/path/to/MySong.logicx"
)

// Use the database
let trackService = TrackMappingService()
let mappings = try await trackService.loadMapping()
```

### Using Conversation Storage

```swift
let convService = ConversationStorageService()

// Save a user message
let messageID = try await convService.saveMessage(
    role: "user",
    content: "Increase the bass on track 1",
    model: "claude-sonnet-4-5",
    generateEmbedding: true
)

// Save an assistant response
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

## Performance Considerations

- **Indexes**: The schema includes optimized indexes for common queries
- **Connection Pooling**: Consider using a connection pool for production
- **Vector Search**: HNSW index is used for fast approximate nearest neighbor search
- **Partitioning**: Consider partitioning messages table for large datasets

## Security

For production deployments:

1. Change default passwords
2. Use SSL/TLS connections
3. Implement row-level security (RLS) if needed
4. Regular backups
5. Monitor database logs

## Additional Resources

- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [Ollama Documentation](https://ollama.ai/docs)
