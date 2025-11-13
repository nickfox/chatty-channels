-- ============================================================================
-- Chatty Channels Database Schema
-- PostgreSQL with pg_vector extension for semantic search
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ============================================================================
-- PROJECTS TABLE
-- Stores Logic Pro project metadata
-- ============================================================================
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,  -- Matches Logic Pro project name
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_opened_at TIMESTAMP WITH TIME ZONE,

    -- Project settings/metadata
    logic_project_path TEXT,  -- Full path to .logicx file
    track_count INTEGER DEFAULT 0,
    sample_rate INTEGER,

    -- Soft delete support
    deleted_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT projects_name_not_empty CHECK (char_length(name) > 0)
);

CREATE INDEX idx_projects_name ON projects(name);
CREATE INDEX idx_projects_last_opened ON projects(last_opened_at DESC);
CREATE INDEX idx_projects_deleted ON projects(deleted_at) WHERE deleted_at IS NULL;

-- ============================================================================
-- SESSIONS TABLE
-- Tracks distinct working sessions within a project
-- ============================================================================
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE,

    -- Session metadata
    is_active BOOLEAN DEFAULT TRUE,
    message_count INTEGER DEFAULT 0,

    CONSTRAINT sessions_project_fk FOREIGN KEY (project_id)
        REFERENCES projects(id) ON DELETE CASCADE
);

CREATE INDEX idx_sessions_project ON sessions(project_id, started_at DESC);
CREATE INDEX idx_sessions_active ON sessions(is_active) WHERE is_active = TRUE;

-- ============================================================================
-- MESSAGES TABLE
-- Stores all user and LLM conversation messages with embeddings
-- ============================================================================
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,

    -- Message content
    role VARCHAR(20) NOT NULL,  -- 'user', 'assistant', 'system'
    content TEXT NOT NULL,

    -- Embeddings for semantic search (nomic-text-embed produces 768-dim vectors)
    embedding vector(768),

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Message metadata
    token_count INTEGER,
    model VARCHAR(100),  -- e.g., 'gpt-4', 'claude-sonnet-4-5', etc.

    -- Context flags
    is_key_decision BOOLEAN DEFAULT FALSE,  -- e.g., "reduced bass by 3dB"
    decision_summary TEXT,  -- Brief summary if is_key_decision = true

    CONSTRAINT messages_role_check CHECK (role IN ('user', 'assistant', 'system')),
    CONSTRAINT messages_content_not_empty CHECK (char_length(content) > 0)
);

-- Indexes for efficient retrieval
CREATE INDEX idx_messages_project_session ON messages(project_id, session_id, created_at DESC);
CREATE INDEX idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX idx_messages_key_decisions ON messages(is_key_decision) WHERE is_key_decision = TRUE;

-- Vector index for semantic similarity search (HNSW algorithm)
CREATE INDEX idx_messages_embedding ON messages USING hnsw (embedding vector_cosine_ops);

-- ============================================================================
-- MISSION_CONTROL_CONVERSATIONS TABLE
-- Stores producer<->user conversation for Mission Control UI
-- (User-facing view - what the producer and user are discussing)
-- ============================================================================
CREATE TABLE mission_control_conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    message_id UUID REFERENCES messages(id) ON DELETE CASCADE,

    -- Conversation entry
    role VARCHAR(20) NOT NULL,  -- 'user' or 'producer'
    content TEXT NOT NULL,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Display metadata
    display_type VARCHAR(50) DEFAULT 'chat',  -- 'chat', 'action', 'status'

    CONSTRAINT mc_conv_role_check CHECK (role IN ('user', 'producer'))
);

CREATE INDEX idx_mc_conv_project_session ON mission_control_conversations(project_id, session_id, created_at DESC);
CREATE INDEX idx_mc_conv_message ON mission_control_conversations(message_id);

-- ============================================================================
-- MISSION_CONTROL_DEBUG TABLE
-- Stores agent<->orchestrator messages for debug mode in Mission Control
-- (Developer view - internal system communications)
-- ============================================================================
CREATE TABLE mission_control_debug (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,

    -- Agent/orchestrator communication
    sender VARCHAR(100) NOT NULL,  -- 'orchestrator', 'osc_agent', 'applescript_agent', 'calculations_agent', etc.
    receiver VARCHAR(100),  -- Target agent/orchestrator, NULL for broadcasts

    -- Message details
    message_type VARCHAR(50) NOT NULL,  -- 'command', 'response', 'status', 'error', 'log'
    content TEXT NOT NULL,
    payload JSONB,  -- Structured data (e.g., track assignments, OSC messages)

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Debugging metadata
    severity VARCHAR(20) DEFAULT 'info',  -- 'debug', 'info', 'warning', 'error'
    parent_message_id UUID REFERENCES mission_control_debug(id),  -- For request/response pairing

    CONSTRAINT mc_debug_severity_check CHECK (severity IN ('debug', 'info', 'warning', 'error'))
);

CREATE INDEX idx_mc_debug_project_session ON mission_control_debug(project_id, session_id, created_at DESC);
CREATE INDEX idx_mc_debug_sender ON mission_control_debug(sender);
CREATE INDEX idx_mc_debug_severity ON mission_control_debug(severity);
CREATE INDEX idx_mc_debug_parent ON mission_control_debug(parent_message_id) WHERE parent_message_id IS NOT NULL;

-- GIN index for JSONB payload queries
CREATE INDEX idx_mc_debug_payload ON mission_control_debug USING gin(payload);

-- ============================================================================
-- TRACK_ASSIGNMENTS TABLE
-- Stores current track-to-plugin mappings (snapshot from AppleScript agent)
-- Not full AppleScript results, just the essential mapping
-- ============================================================================
CREATE TABLE track_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,

    -- Track information
    track_number INTEGER NOT NULL,
    track_name VARCHAR(255) NOT NULL,
    plugin_id VARCHAR(50) NOT NULL,  -- e.g., "TR1", "TR2"

    -- Assignment metadata
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    verified_at TIMESTAMP WITH TIME ZONE,  -- Last OSC ping confirmation
    is_current BOOLEAN DEFAULT TRUE,  -- Only one current assignment per track per session

    CONSTRAINT track_assignments_track_num_positive CHECK (track_number > 0)
);

CREATE INDEX idx_track_assignments_project_session ON track_assignments(project_id, session_id, is_current);
CREATE INDEX idx_track_assignments_plugin ON track_assignments(plugin_id);
CREATE UNIQUE INDEX idx_track_assignments_current ON track_assignments(project_id, session_id, track_number, is_current)
    WHERE is_current = TRUE;

-- ============================================================================
-- CONTEXT_SNAPSHOTS TABLE
-- Optional: Store snapshots of important moments (e.g., "before mastering")
-- Can be referenced later for retrieval
-- ============================================================================
CREATE TABLE context_snapshots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,

    -- Snapshot metadata
    name VARCHAR(255) NOT NULL,  -- e.g., "Before Mastering", "Final Mix"
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Snapshot content
    message_ids UUID[] NOT NULL,  -- Array of message IDs included in snapshot
    track_state JSONB,  -- Track volumes, pans, effects at snapshot time

    CONSTRAINT context_snapshots_messages_not_empty CHECK (array_length(message_ids, 1) > 0)
);

CREATE INDEX idx_context_snapshots_project ON context_snapshots(project_id, created_at DESC);
CREATE INDEX idx_context_snapshots_session ON context_snapshots(session_id);

-- ============================================================================
-- VIEWS
-- Convenient queries for common access patterns
-- ============================================================================

-- Recent conversation context (last 10 messages)
CREATE VIEW recent_messages AS
SELECT
    m.*,
    p.name AS project_name,
    s.started_at AS session_started
FROM messages m
JOIN projects p ON m.project_id = p.id
JOIN sessions s ON m.session_id = s.id
WHERE s.is_active = TRUE
ORDER BY m.created_at DESC
LIMIT 10;

-- Active session summary
CREATE VIEW active_sessions AS
SELECT
    s.id AS session_id,
    s.project_id,
    p.name AS project_name,
    s.started_at,
    COUNT(m.id) AS message_count,
    MAX(m.created_at) AS last_message_at
FROM sessions s
JOIN projects p ON s.project_id = p.id
LEFT JOIN messages m ON s.id = m.session_id
WHERE s.is_active = TRUE
GROUP BY s.id, s.project_id, p.name, s.started_at;

-- Current track assignments per project
CREATE VIEW current_track_assignments AS
SELECT
    ta.project_id,
    p.name AS project_name,
    ta.session_id,
    ta.track_number,
    ta.track_name,
    ta.plugin_id,
    ta.assigned_at,
    ta.verified_at
FROM track_assignments ta
JOIN projects p ON ta.project_id = p.id
WHERE ta.is_current = TRUE
ORDER BY ta.project_id, ta.track_number;

-- Mission Control complete view (conversations + debug)
CREATE VIEW mission_control_complete AS
SELECT
    'conversation' AS source_type,
    mc.id,
    mc.project_id,
    mc.session_id,
    mc.created_at,
    mc.role AS sender,
    NULL AS receiver,
    mc.content,
    mc.display_type AS type_detail,
    NULL AS payload
FROM mission_control_conversations mc
UNION ALL
SELECT
    'debug' AS source_type,
    md.id,
    md.project_id,
    md.session_id,
    md.created_at,
    md.sender,
    md.receiver,
    md.content,
    md.message_type AS type_detail,
    md.payload
FROM mission_control_debug md
ORDER BY created_at DESC;

-- ============================================================================
-- FUNCTIONS
-- Helper functions for common operations
-- ============================================================================

-- Update project's updated_at timestamp
CREATE OR REPLACE FUNCTION update_project_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE projects SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.project_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update project timestamp on new message
CREATE TRIGGER trigger_update_project_on_message
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION update_project_timestamp();

-- Increment session message count
CREATE OR REPLACE FUNCTION increment_session_message_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE sessions SET message_count = message_count + 1 WHERE id = NEW.session_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_increment_message_count
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION increment_session_message_count();

-- Function to get context for retrieval (hybrid: semantic + recency + last 10)
CREATE OR REPLACE FUNCTION get_conversation_context(
    p_project_id UUID,
    p_query_embedding vector(768),
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    message_id UUID,
    content TEXT,
    role VARCHAR,
    created_at TIMESTAMP WITH TIME ZONE,
    similarity FLOAT,
    is_recent BOOLEAN,
    is_key_decision BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    WITH semantic_matches AS (
        -- Get semantically similar messages
        SELECT
            m.id,
            m.content,
            m.role,
            m.created_at,
            1 - (m.embedding <=> p_query_embedding) AS similarity,
            FALSE AS is_recent,
            m.is_key_decision
        FROM messages m
        WHERE m.project_id = p_project_id
            AND m.embedding IS NOT NULL
        ORDER BY m.embedding <=> p_query_embedding
        LIMIT p_limit / 2
    ),
    recent_messages AS (
        -- Always include last 10 messages
        SELECT
            m.id,
            m.content,
            m.role,
            m.created_at,
            0.0 AS similarity,
            TRUE AS is_recent,
            m.is_key_decision
        FROM messages m
        WHERE m.project_id = p_project_id
        ORDER BY m.created_at DESC
        LIMIT 10
    ),
    key_decisions AS (
        -- Include key decisions from last 7 days
        SELECT
            m.id,
            m.content,
            m.role,
            m.created_at,
            0.0 AS similarity,
            FALSE AS is_recent,
            m.is_key_decision
        FROM messages m
        WHERE m.project_id = p_project_id
            AND m.is_key_decision = TRUE
            AND m.created_at > CURRENT_TIMESTAMP - INTERVAL '7 days'
        ORDER BY m.created_at DESC
        LIMIT 5
    )
    SELECT DISTINCT ON (cm.id)
        cm.id,
        cm.content,
        cm.role,
        cm.created_at,
        cm.similarity,
        cm.is_recent,
        cm.is_key_decision
    FROM (
        SELECT * FROM semantic_matches
        UNION
        SELECT * FROM recent_messages
        UNION
        SELECT * FROM key_decisions
    ) cm
    ORDER BY cm.id, cm.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SAMPLE QUERIES
-- Common queries for the application
-- ============================================================================

-- Get or create project by name
-- Example: SELECT * FROM get_or_create_project('MySong.logicx');
CREATE OR REPLACE FUNCTION get_or_create_project(p_name VARCHAR)
RETURNS UUID AS $$
DECLARE
    v_project_id UUID;
BEGIN
    SELECT id INTO v_project_id FROM projects WHERE name = p_name AND deleted_at IS NULL;

    IF v_project_id IS NULL THEN
        INSERT INTO projects (name, last_opened_at)
        VALUES (p_name, CURRENT_TIMESTAMP)
        RETURNING id INTO v_project_id;
    ELSE
        UPDATE projects SET last_opened_at = CURRENT_TIMESTAMP WHERE id = v_project_id;
    END IF;

    RETURN v_project_id;
END;
$$ LANGUAGE plpgsql;

-- Start a new session
CREATE OR REPLACE FUNCTION start_session(p_project_id UUID)
RETURNS UUID AS $$
DECLARE
    v_session_id UUID;
BEGIN
    -- End any active sessions for this project
    UPDATE sessions SET is_active = FALSE, ended_at = CURRENT_TIMESTAMP
    WHERE project_id = p_project_id AND is_active = TRUE;

    -- Create new session
    INSERT INTO sessions (project_id)
    VALUES (p_project_id)
    RETURNING id INTO v_session_id;

    RETURN v_session_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- Additional indexes for common query patterns
-- ============================================================================

-- Composite index for context retrieval
CREATE INDEX idx_messages_context_retrieval ON messages(project_id, created_at DESC, is_key_decision);

-- Index for recent messages in active sessions
CREATE INDEX idx_messages_active_sessions ON messages(session_id, created_at DESC)
    WHERE session_id IN (SELECT id FROM sessions WHERE is_active = TRUE);

-- ============================================================================
-- COMMENTS ok
-- Documentation for schema elements
-- ============================================================================

COMMENT ON TABLE projects IS 'Logic Pro projects with metadata';
COMMENT ON TABLE sessions IS 'Working sessions within projects';
COMMENT ON TABLE messages IS 'User and LLM conversation messages with embeddings for semantic search';
COMMENT ON TABLE mission_control_conversations IS 'User-facing producer<->user conversation log';
COMMENT ON TABLE mission_control_debug IS 'Developer debug view of agent<->orchestrator communications';
COMMENT ON TABLE track_assignments IS 'Current track-to-plugin mappings from AppleScript verification';
COMMENT ON TABLE context_snapshots IS 'Snapshots of important project moments for later reference';

COMMENT ON COLUMN messages.embedding IS 'Vector embedding from nomic-text-embed (768 dimensions)';
COMMENT ON COLUMN messages.is_key_decision IS 'Marks important decisions like "reduced bass by 3dB"';
COMMENT ON COLUMN mission_control_debug.payload IS 'Structured JSON data for agent messages';

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
