-- GitHub-style labels replace the single category plus free-form tag array.
CREATE TABLE labels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  color TEXT NOT NULL CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_labels_name_lower ON labels (lower(name));

ALTER TABLE labels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON labels FOR ALL USING (true);

CREATE TABLE transaction_labels (
  transaction_id UUID NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  label_id UUID NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (transaction_id, label_id)
);

CREATE INDEX idx_transaction_labels_label_id ON transaction_labels(label_id);

ALTER TABLE transaction_labels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON transaction_labels FOR ALL USING (true);

-- Preserve existing categories and tags as reusable labels before removing them.
INSERT INTO labels (name, color)
SELECT DISTINCT source.name, '#1D76DB'
FROM (
  SELECT NULLIF(BTRIM(category), '') AS name FROM transactions
  UNION
  SELECT NULLIF(BTRIM(tag), '') AS name
  FROM transactions, UNNEST(tags) AS tag
) AS source
WHERE source.name IS NOT NULL
ON CONFLICT ((lower(name))) DO NOTHING;

INSERT INTO transaction_labels (transaction_id, label_id)
SELECT DISTINCT source.transaction_id, labels.id
FROM (
  SELECT id AS transaction_id, NULLIF(BTRIM(category), '') AS name
  FROM transactions
  UNION ALL
  SELECT id AS transaction_id, NULLIF(BTRIM(tag), '') AS name
  FROM transactions, UNNEST(tags) AS tag
) AS source
JOIN labels ON lower(labels.name) = lower(source.name)
WHERE source.name IS NOT NULL
ON CONFLICT DO NOTHING;

ALTER TABLE transactions
  DROP COLUMN category,
  DROP COLUMN tags;

ALTER PUBLICATION supabase_realtime ADD TABLE labels;
ALTER PUBLICATION supabase_realtime ADD TABLE transaction_labels;
