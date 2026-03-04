-- migrate:up
ALTER TABLE users ADD COLUMN age INT NOT NULL;

-- migrate:down
ALTER TABLE users DROP COLUMN age;
