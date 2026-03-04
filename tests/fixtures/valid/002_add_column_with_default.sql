-- migrate:up
ALTER TABLE users ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active';

-- migrate:down
ALTER TABLE users DROP COLUMN status;
