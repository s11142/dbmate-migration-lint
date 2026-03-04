-- migrate:up
CREATE TABLE bad_table (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

-- migrate:down
DROP TABLE bad_table;
