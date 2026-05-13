-- Domains: coded value and range domains
CREATE TABLE IF NOT EXISTS domains (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    domain_type TEXT NOT NULL,  -- 'coded_value' or 'range'
    field_type TEXT NOT NULL,   -- 'string', 'integer', 'float'
    coded_values JSONB,         -- [{code: val, name: "label"}, ...]
    range_min DOUBLE PRECISION,
    range_max DOUBLE PRECISION,
    description TEXT
);

-- Subtypes: subtype-specific schemas
CREATE TABLE IF NOT EXISTS subtypes (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    subtype_field TEXT NOT NULL,
    code INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    default_values JSONB NOT NULL DEFAULT '{}',
    domain_assignments JSONB NOT NULL DEFAULT '{}'  -- {field_name: domain_id}
);

-- Attribute rules: calculated fields and constraints
CREATE TABLE IF NOT EXISTS attribute_rules (
    id UUID PRIMARY KEY,
    dataset_id UUID NOT NULL REFERENCES datasets(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    rule_type TEXT NOT NULL,  -- 'calculation', 'constraint', 'validation'
    trigger_event TEXT NOT NULL DEFAULT 'insert,update',  -- comma-separated: insert, update, delete
    field_name TEXT,           -- target field for calculations
    expression TEXT NOT NULL,  -- expression to evaluate (simplified expression language)
    error_message TEXT,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    execution_order INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_domains_dataset ON domains(dataset_id);
CREATE INDEX IF NOT EXISTS idx_subtypes_dataset ON subtypes(dataset_id);
CREATE INDEX IF NOT EXISTS idx_attr_rules_dataset ON attribute_rules(dataset_id);
